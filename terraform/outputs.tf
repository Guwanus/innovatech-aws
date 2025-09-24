output "alb_dns_name" {
  description = "Public DNS van de Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "db_endpoint" {
  description = "RDS endpoint hostname"
  value       = aws_db_instance.db.address
}

output "db_connection_string" {
  description = "Handige psql connection string"
  value       = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.db.address}:5432/${var.db_name}"
  sensitive   = true
}
