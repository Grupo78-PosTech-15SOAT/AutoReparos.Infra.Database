variable "aws_region" {
  description = "Região da AWS para provisionamento do RDS"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente de deploy (production, staging, development)"
  type        = string
  default     = "production"
}

variable "vpc_id" {
  description = "VPC ID exported by the network Terraform state"
  type        = string
  validation {
    condition     = startswith(var.vpc_id, "vpc-")
    error_message = "vpc_id must be passed from the network state."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs exported by the network Terraform state"
  type        = list(string)
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least two private subnet IDs must be passed explicitly."
  }
}

variable "allowed_security_group_ids" {
  description = "Only the EKS node and shared Lambda security groups may connect to PostgreSQL"
  type        = list(string)
  validation {
    condition     = length(var.allowed_security_group_ids) >= 2 && alltrue([for id in var.allowed_security_group_ids : startswith(id, "sg-")])
    error_message = "Pass the EKS and Lambda security group IDs from the network layer."
  }
}

variable "allowed_cidr_blocks" {
  description = "Blocos CIDR adicionais autorizados para acesso ao PostgreSQL (ex: VPN corporativa ou subnets internas)"
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.allowed_cidr_blocks) == 0
    error_message = "Use security group IDs for database access; CIDR based ingress is disabled."
  }
}

variable "db_name" {
  description = "Nome do banco de dados relacional inicial"
  type        = string
  default     = "autoreparos_db"
}

variable "db_username" {
  description = "Nome do usuário administrador do PostgreSQL"
  type        = string
  default     = "autoreparos_admin"
}

variable "db_password" {
  description = "Senha do usuário administrador. Se vazia, será gerada automaticamente uma senha forte via random_password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "db_allocated_storage" {
  description = "Tamanho inicial do disco em GiB"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Tamanho máximo para autoscaling de armazenamento do PostgreSQL em GiB"
  type        = number
  default     = 100
}

variable "db_instance_class" {
  description = "Instância computacional do RDS (db.t4g.micro é elegível para otimização de custo/Free Tier)"
  type        = string
  default     = "db.t4g.micro"
}

variable "backup_retention_period" {
  description = "Dias de retenção dos backups automatizados diários (1 dia no AWS Free Plan; reavaliar para produção fora desse plano)"
  type        = number
  default     = 1
}

variable "backup_window" {
  description = "Janela diária em UTC para execução dos backups"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Janela semanal em UTC para manutenção do RDS"
  type        = string
  default     = "Sun:04:30-Sun:05:30"
}

variable "multi_az" {
  description = "Habilitar RDS Multi-AZ para alta disponibilidade e failover automático"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Proteção contra deleção acidental da instância RDS"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Determina se um snapshot final deve ser ignorado na destruição (false garante snapshot de resgate)"
  type        = bool
  default     = false
}

variable "final_snapshot_identifier" {
  description = "Unique final snapshot name used by the centrally approved teardown workflow"
  type        = string
  default     = "autoreparos-rds-production-final"
}
