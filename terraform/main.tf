# 1. Geração de Senha Segura Automática (se não fornecida explicitamente)
resource "random_password" "master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

locals {
  effective_password = var.db_password != "" ? var.db_password : random_password.master_password.result
}

# 2. Subnet Group em Subnets Privadas
resource "aws_db_subnet_group" "rds" {
  name        = "autoreparos-db-subnet-group-${var.environment}"
  description = "Subnet Group dedicado para o PostgreSQL RDS do AutoReparos em subnets privadas"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "autoreparos-db-subnet-group-${var.environment}"
  }
}

# 3. Security Group Restrito para o RDS (Porta 5432)
resource "aws_security_group" "rds" {
  name        = "autoreparos-rds-sg-${var.environment}"
  description = "Security group restrito para o banco de dados RDS PostgreSQL"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_security_group_ids) > 0 ? [1] : []
    content {
      description     = "Acesso PostgreSQL a partir dos Security Groups autorizados (EKS e Lambda)"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = var.allowed_security_group_ids
    }
  }

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Acesso PostgreSQL a partir de CIDRs autorizados"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    description = "Permitir qualquer saida do SG do RDS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "autoreparos-rds-sg-${var.environment}"
  }
}

# 4. Parameter Group Customizado para PostgreSQL 16
resource "aws_db_parameter_group" "pg16" {
  name        = "autoreparos-pg16-params-${var.environment}"
  family      = "postgres16"
  description = "Parameter Group otimizado para PostgreSQL 16 no AutoReparos"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "0"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Loga consultas com duracao > 1000ms
  }

  tags = {
    Name = "autoreparos-pg16-params-${var.environment}"
  }
}

# 5. Instância AWS RDS PostgreSQL 16
resource "aws_db_instance" "postgres" {
  identifier            = "autoreparos-rds-${var.environment}"
  engine                = "postgres"
  engine_version        = "16.3"
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = local.effective_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.pg16.name

  multi_az                   = var.multi_az
  publicly_accessible        = false
  backup_retention_period    = var.backup_retention_period
  backup_window              = "03:00-04:00"
  maintenance_window         = "Sun:04:30-Sun:05:30"
  copy_tags_to_snapshot      = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  auto_minor_version_upgrade = true

  tags = {
    Name = "autoreparos-rds-${var.environment}"
  }
}

# 6. AWS Secrets Manager para Armazenamento Seguro de Credenciais
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "autoreparos/${var.environment}/database/credentials"
  description             = "Credenciais de acesso ao AWS RDS PostgreSQL 16 para AutoReparos.App e AutoReparos.AuthLambda"
  recovery_window_in_days = 0

  tags = {
    Name = "autoreparos-db-credentials-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    engine           = "postgres"
    host             = aws_db_instance.postgres.address
    port             = aws_db_instance.postgres.port
    dbname           = var.db_name
    username         = var.db_username
    password         = local.effective_password
    connectionString = "Host=${aws_db_instance.postgres.address};Port=${aws_db_instance.postgres.port};Database=${var.db_name};Username=${var.db_username};Password=${local.effective_password};SSL Mode=Prefer;"
  })
}
