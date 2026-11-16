# Provisionador da database de cada serviço (D-54): única role com a credencial admin do RDS.
# O pipeline de cada serviço chama a Function URL assinando com autoreparos-deploy-<servico>
# (criada pela plataforma no Infra.K8s); a Lambda deduz o serviço dessa role.

locals {
  provisionador_nome     = "autoreparos-provisionador-db"
  provisionador_servicos = toset(["os", "cobranca", "execucao", "cadastros"])
  provisionador_roles_deploy = {
    for servico in local.provisionador_servicos :
    servico => "arn:aws:iam::${var.conta_aws_id}:role/autoreparos-deploy-${servico}"
  }
  provisionador_segredos_servicos = "arn:aws:secretsmanager:${var.aws_region}:${var.conta_aws_id}:secret:autoreparos/${var.environment}/*/database-??????"
}

# Pacote gerado por lambda/provisionador/empacotar.sh (código + pg8000).
data "archive_file" "provisionador" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/provisionador/build"
  output_path = "${path.module}/.build/provisionador.zip"
}

resource "aws_security_group" "provisionador" {
  name        = "${local.provisionador_nome}-sg"
  description = "Lambda autoreparos-provisionador-db: saida so para o RDS e HTTPS"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.provisionador_nome}-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "provisionador_rds" {
  security_group_id            = aws_security_group.provisionador.id
  description                  = "PostgreSQL no RDS"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds.id
}

resource "aws_vpc_security_group_egress_rule" "provisionador_https" {
  security_group_id = aws_security_group.provisionador.id
  description       = "Secrets Manager pelo NAT"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_iam_role" "provisionador" {
  name        = local.provisionador_nome
  description = "Execucao da Lambda autoreparos-provisionador-db; unica role com a credencial admin do RDS (D-54)"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "provisionador_vpc" {
  role       = aws_iam_role.provisionador.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "provisionador_segredos" {
  name = "segredos-database"
  role = aws_iam_role.provisionador.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LeCredencialAdminESegredosDosServicos"
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.db_credentials.arn,
        local.provisionador_segredos_servicos,
      ]
    }]
  })
}

resource "aws_cloudwatch_log_group" "provisionador" {
  name              = "/aws/lambda/${local.provisionador_nome}"
  retention_in_days = 14
}

resource "aws_lambda_function" "provisionador" {
  function_name    = local.provisionador_nome
  description      = "Cria a database e o usuario do servico da role de deploy que chamou (D-54)"
  role             = aws_iam_role.provisionador.arn
  runtime          = "python3.12"
  handler          = "provisionador.handler"
  filename         = data.archive_file.provisionador.output_path
  source_code_hash = data.archive_file.provisionador.output_base64sha256
  timeout          = 30
  memory_size      = 128

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.provisionador.id]
  }

  environment {
    variables = {
      ADMIN_SECRET_ARN  = aws_secretsmanager_secret.db_credentials.arn
      AMBIENTE          = var.environment
      DB_NAME_CADASTROS = var.db_name
      CONTA_AWS         = var.conta_aws_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.provisionador_vpc,
    aws_iam_role_policy.provisionador_segredos,
    aws_cloudwatch_log_group.provisionador,
  ]
}

resource "aws_lambda_function_url" "provisionador" {
  function_name      = aws_lambda_function.provisionador.function_name
  authorization_type = "AWS_IAM"
}

# Política de recurso: só as 4 roles de deploy invocam, e só pela Function URL.
resource "aws_lambda_permission" "provisionador_url" {
  for_each = local.provisionador_roles_deploy

  statement_id           = "InvokeFunctionUrl-${each.key}"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.provisionador.function_name
  principal              = each.value
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "provisionador_invoke" {
  for_each = local.provisionador_roles_deploy

  statement_id             = "InvokeFunction-${each.key}"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.provisionador.function_name
  principal                = each.value
  invoked_via_function_url = true
}

resource "aws_ssm_parameter" "provisionador_url" {
  name        = "/autoreparos/${var.environment}/provisionador-db/url"
  description = "Function URL do autoreparos-provisionador-db (AuthType AWS_IAM)"
  type        = "String"
  value       = aws_lambda_function_url.provisionador.function_url
  overwrite   = true

  tags = {
    Environment = var.environment
  }
}
