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
  description = "ID da VPC onde o RDS será provisionado. Se vazio, será auto-descoberta via tag Name"
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Lista de IDs das Subnets privadas para o DB Subnet Group. Se vazia, será auto-descoberta via tags na VPC"
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Lista de IDs de Security Groups autorizados a acessar o PostgreSQL na porta 5432 (ex: Security Group do EKS e da Lambda)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "Blocos CIDR adicionais autorizados para acesso ao PostgreSQL (ex: VPN corporativa ou subnets internas)"
  type        = list(string)
  default     = []
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
  description = "Dias de retenção dos backups automatizados diários (mínimo 7 dias recomendado para produção)"
  type        = number
  default     = 7
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
