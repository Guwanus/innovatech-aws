variable "region" {
  type    = string
  default = "eu-central-1" # Frankfurt
}

variable "name" {
  type    = string
  default = "innovatech"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
  validation {
    condition = contains([
      "t2.nano", "t2.micro", "t2.small", "t2.medium", "t2.large", "t2.2xlarge",
      "t3.nano", "t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge",
      "t3a.medium", "t2a.nano",
      "t4g.nano", "t4g.micro", "t4g.small", "t4g.medium",
      "c5.large",
      "c6g.medium", "c6gd.medium", "c6gn.medium",
      "c7g.medium", "c7gd.medium",
      "c8g.medium",
      "a1.medium", "a1.large", "a1.xlarge",
      "m6g.medium", "m7g.medium", "m8g.medium"
    ], var.instance_type)
    error_message = "Instance type niet toegestaan door onderwijs-limieten."
  }
}

variable "tags" {
  type = map(string)
  default = {
    Project = "innovatech-aws"
    Env     = "dev"
  }
}

# ---- RDS variabelen ----
variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
  validation {
    condition = contains([
      "db.t2.micro", "db.t2.small",
      "db.t3.micro", "db.t3.small", "db.t3.medium",
      "db.t4g.micro", "db.t4g.small", "db.t4g.medium",
      "db.m4.large", "db.r4.large"
    ], var.db_instance_class)
    error_message = "RDS instance class niet toegestaan door onderwijs-limieten."
  }
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appuser"
}

variable "db_password" {
  type      = string
  sensitive = true
}

# ---- Auto Scaling variabelen ----
variable "asg_desired" {
  type    = number
  default = 2
}

variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_max" {
  type    = number
  default = 6
}

variable "asg_cpu_target_percent" {
  type    = number
  default = 50
}

variable "asg_req_per_target" {
  type    = number
  default = 100
}