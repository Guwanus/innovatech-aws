# -------------- Network --------------
resource "aws_vpc" "this" {
  cidr_block           = "10.70.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "${var.name}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

# Twee public subnets in 2 AZ's
data "aws_availability_zones" "available" {}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.70.0.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${var.name}-public-a" })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.70.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${var.name}-public-b" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(var.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "pub_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# -------------- Security Groups --------------
# ALB SG -> open op 80 naar internet
resource "aws_security_group" "alb" {
  name   = "${var.name}-alb-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from Internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-alb-sg" })
}

# Web SG -> 80 vanaf ALB, egress overal
resource "aws_security_group" "web" {
  name   = "${var.name}-web-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTP from ALB"
  }

  # (Optioneel) SSH vanaf jouw IP
  # ingress {
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["YOUR.PUBLIC.IP.ADDR/32"]
  #   description = "SSH from your IP"
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-web-sg" })
}

# DB SG -> 5432 alleen vanaf web-SG
resource "aws_security_group" "db" {
  name   = "${var.name}-db-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
    description     = "Postgres from web SG"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-db-sg" })
}

# -------------- ALB --------------
resource "aws_lb" "app" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  idle_timeout       = 60
  tags               = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_lb_target_group" "tg" {
  name        = "${var.name}-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

  health_check {
    path    = "/"
    matcher = "200-399"
  }

  tags = merge(var.tags, { Name = "${var.name}-tg" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# -------------- EC2 Webservers --------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"] # Amazon
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# RDS endpoint in user_data -> web instances wachten automatisch tot DB gepland is
locals {
  user_data = <<-EOT
    #!/bin/bash
    set -eux
    dnf update -y
    dnf install -y nginx

    # .env met DB-gegevens voor je app
    install -d -m 0755 /etc/app
    cat >/etc/app/.env <<EOF
    DB_HOST=${aws_db_instance.db.address}
    DB_NAME=${var.db_name}
    DB_USER=${var.db_username}
    DB_PASS=${var.db_password}
    EOF
    chmod 600 /etc/app/.env

    # Demo HTML
    cat >/usr/share/nginx/html/index.html <<HTML
    <html><body style="font-family: Arial; margin: 2rem;">
      <h1>${var.name} - Hello from $(hostname)</h1>
      <p>AZ: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>
      <h3>Database connection (for app):</h3>
      <pre>/etc/app/.env</pre>
    </body></html>
    HTML

    systemctl enable --now nginx
  EOT
}

resource "aws_instance" "web_a" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  user_data                   = local.user_data

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(var.tags, { Name = "${var.name}-web-a", Role = "web" })
}

resource "aws_instance" "web_b" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_b.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  user_data                   = local.user_data

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(var.tags, { Name = "${var.name}-web-b", Role = "web" })
}

# Koppel beide instances aan de target group
resource "aws_lb_target_group_attachment" "a" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web_a.id
  port             = 80
}
resource "aws_lb_target_group_attachment" "b" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web_b.id
  port             = 80
}

# -------------- RDS Postgres --------------
resource "aws_db_subnet_group" "db" {
  name       = "${var.name}-db-subnets"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id] # simpel: dezelfde 2 AZ's
  tags       = merge(var.tags, { Name = "${var.name}-db-subnets" })
}

resource "aws_db_parameter_group" "pg" {
  name        = "${var.name}-pg14"
  family      = "postgres14"
  description = "Basic params"
  tags        = var.tags
}

resource "aws_db_instance" "db" {
  identifier     = "${var.name}-pg"
  engine         = "postgres"
  engine_version = "14"
  instance_class = var.db_instance_class
  db_name        = var.db_name
  username       = var.db_username
  password       = var.db_password

  allocated_storage     = var.db_allocated_storage_gb
  storage_type          = "gp2"
  max_allocated_storage = 0

  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.pg.name

  multi_az                     = false
  publicly_accessible          = false
  backup_retention_period      = 1
  deletion_protection          = false
  skip_final_snapshot          = true
  storage_encrypted            = true
  performance_insights_enabled = false

  tags = merge(var.tags, { Name = "${var.name}-pg" })
}
