##############################
# Variables for Grafana/SSH  #
##############################

variable "ssh_key_name" {
  description = "Name of an existing AWS key pair for SSH. Leave empty to disable SSH key injection."
  type        = string
  default     = ""
}

variable "ssh_allow_cidrs" {
  description = "CIDRs that may SSH to Grafana."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "grafana_instance_type" {
  description = "Instance type for the Grafana EC2."
  type        = string
  default     = "t3.small"
}

variable "grafana_allow_cidrs" {
  description = "CIDRs allowed to access Grafana UI (3000)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

##############################
# Variables for Prometheus   #
##############################

variable "prometheus_version" {
  description = "Prometheus version to install on web servers."
  type        = string
  default     = "2.54.1"
}
