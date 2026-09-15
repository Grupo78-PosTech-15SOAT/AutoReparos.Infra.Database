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
  description = "ID da VPC onde o RDS será provisionado"
  type        = string
}

variable "private_subnet_ids" {
  description = "Lista de IDs das Subnets privadas para o DB Subnet Group (mínimo 2 em AZs distintas)"
  type        = list(string)
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

variable "instance_class" {
  description = "Tipo de instância do RDS PostgreSQL"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Armazenamento inicial alocado em GiB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Limite máximo para auto-scaling de armazenamento em GiB (20 GiB mantem perfil Free Tier)"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Habilitar implantação Multi-AZ para alta disponibilidade"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Dias de retenção de backups automatizados do RDS (1 dia para compatibilidade com Free Tier)"
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Proteção contra exclusão acidental do banco de dados"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Ignorar snapshot final ao destruir o banco (definir como false em produção real)"
  type        = bool
  default     = true
}
