output "db_endpoint" {
  description = "Endpoint de conexao do banco de dados RDS (host:porta)"
  value       = aws_db_instance.postgres.endpoint
}

output "db_address" {
  description = "Endereco DNS (host) do banco de dados RDS"
  value       = aws_db_instance.postgres.address
}

output "db_port" {
  description = "Porta do banco de dados PostgreSQL"
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "Nome do banco de dados relacional"
  value       = aws_db_instance.postgres.db_name
}

output "db_username" {
  description = "Nome de usuario administrador do PostgreSQL"
  value       = aws_db_instance.postgres.username
  sensitive   = true
}

output "db_security_group_id" {
  description = "ID do Security Group restrito criado para o RDS"
  value       = aws_security_group.rds.id
}

output "db_instance_id" {
  description = "Identificador da instancia RDS PostgreSQL"
  value       = aws_db_instance.postgres.id
}

output "db_secret_arn" {
  description = "ARN do segredo no AWS Secrets Manager contendo as credenciais do banco"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_connection_string" {
  description = "Connection string para aplicacao .NET e Lambda"
  value       = "Host=${aws_db_instance.postgres.address};Port=${aws_db_instance.postgres.port};Database=${var.db_name};Username=${var.db_username};Password=${local.effective_password};SSL Mode=Prefer;"
  sensitive   = true
}
