##############################
# Grafana EC2 (self-hosted)  #
##############################

# Security group for Grafana UI + SSH
resource "aws_security_group" "grafana" {
  name        = "${var.name}-grafana-sg"
  description = "Allow Grafana (3000) from anywhere and SSH (22)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Grafana UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.grafana_allow_cidrs
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allow_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-grafana-sg" })
}

# Allow Prometheus (9090) on the web servers from the Grafana SG
resource "aws_security_group_rule" "prometheus_from_grafana" {
  type                     = "ingress"
  description              = "Allow Prometheus (9090) access from Grafana instance"
  from_port                = 9090
  to_port                  = 9090
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web.id     # target: web SG
  source_security_group_id = aws_security_group.grafana.id # source: grafana SG
}

# Optional: expose node_exporter (9100) from web SG to Grafana (if you enable node_exporter later)
resource "aws_security_group_rule" "node_exporter_from_grafana" {
  type                     = "ingress"
  description              = "Allow node_exporter (9100) access from Grafana instance"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web.id
  source_security_group_id = aws_security_group.grafana.id
}

# Grafana EC2 instance in a public subnet
resource "aws_instance" "grafana" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.grafana_instance_type
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.grafana.id]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name != "" ? var.ssh_key_name : null

  user_data_base64 = base64encode(<<-EOT
    #!/bin/bash
    set -eux
    dnf update -y

    # Install Grafana OSS (Amazon Linux 2023)
    cat >/etc/yum.repos.d/grafana.repo <<'EOF'
    [grafana]
    name=Grafana OSS
    baseurl=https://packages.grafana.com/oss/rpm
    repo_gpgcheck=1
    enabled=1
    gpgcheck=1
    gpgkey=https://packages.grafana.com/gpg.key
    EOF

    dnf install -y grafana
    systemctl enable --now grafana-server

    # Optional: open firewall if firewalld present (usually not on AL2023)
    if command -v firewall-cmd >/dev/null 2>&1; then
      firewall-cmd --add-port=3000/tcp --permanent || true
      firewall-cmd --reload || true
    fi

    # Print quick tips into MOTD
    cat >/etc/motd <<TIP
    Grafana is installed.
    - URL:  http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000
    - Default login: admin / admin
    - Add each webserver's Prometheus as a Data source (type: Prometheus), e.g. http://<webserver-private-ip>:9090
    TIP
  EOT
  )

  tags = merge(var.tags, { Name = "${var.name}-grafana" })
}

output "grafana_url" {
  description = "Grafana URL (HTTP)"
  value       = "http://${aws_instance.grafana.public_ip}:3000"
}
