# C28 (AC 24, D-54): a Lambda autoreparos-provisionador-db fica na VPC com acesso ao RDS, tem
# Function URL AWS_IAM e é a única role com secretsmanager:GetSecretValue na credencial admin.
# Uso, da raiz do pai: scripts/specs/tf_test.sh submodules/AutoReparos.Infra.Database/terraform provisionador

mock_provider "aws" {}
mock_provider "random" {}

mock_provider "archive" {
  mock_data "archive_file" {
    defaults = {
      output_path         = "provisionador.zip"
      output_base64sha256 = "c2hhMjU2LWRvLXBhY290ZS1kby1wcm92aXNpb25hZG9yLWRiLWZhbHNvMDA="
    }
  }
}

variables {
  vpc_id                     = "vpc-0123456789abcdef0"
  private_subnet_ids         = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
  allowed_security_group_ids = ["sg-0eeeeeeeeeeeeeee1"]
}

override_resource {
  target = aws_secretsmanager_secret.db_credentials
  values = {
    arn = "arn:aws:secretsmanager:us-east-1:198903849859:secret:autoreparos/production/database/credentials-AbCdEf"
  }
}

override_resource {
  target = aws_security_group.rds
  values = {
    id = "sg-0aaaaaaaaaaaaaaa0"
  }
}

override_resource {
  target = aws_security_group.provisionador
  values = {
    id = "sg-0bbbbbbbbbbbbbbb0"
  }
}

override_resource {
  target = aws_iam_role.provisionador
  values = {
    arn = "arn:aws:iam::198903849859:role/autoreparos-provisionador-db"
  }
}

override_resource {
  target = aws_lambda_function_url.provisionador
  values = {
    function_url = "https://abc123.lambda-url.us-east-1.on.aws/"
  }
}

run "lambda_na_vpc_com_acesso_ao_rds" {
  command = apply

  assert {
    condition     = aws_lambda_function.provisionador.function_name == "autoreparos-provisionador-db"
    error_message = "A Lambda deve se chamar autoreparos-provisionador-db."
  }

  assert {
    condition     = toset(aws_lambda_function.provisionador.vpc_config[0].subnet_ids) == toset(var.private_subnet_ids)
    error_message = "A Lambda deve rodar nas sub-redes privadas do RDS."
  }

  assert {
    condition     = aws_lambda_function.provisionador.vpc_config[0].security_group_ids == toset([aws_security_group.provisionador.id])
    error_message = "A Lambda deve usar só o security group próprio."
  }

  assert {
    condition     = aws_security_group.provisionador.vpc_id == var.vpc_id
    error_message = "O security group da Lambda deve ficar na VPC do RDS."
  }

  assert {
    condition = anytrue([
      for regra in aws_security_group.rds.ingress :
      regra.from_port == 5432 && regra.to_port == 5432 && regra.protocol == "tcp" && contains(regra.security_groups, aws_security_group.provisionador.id)
    ])
    error_message = "O security group do RDS deve aceitar 5432 vindo do security group da Lambda."
  }

  assert {
    condition = (
      aws_vpc_security_group_egress_rule.provisionador_rds.security_group_id == aws_security_group.provisionador.id &&
      aws_vpc_security_group_egress_rule.provisionador_rds.referenced_security_group_id == aws_security_group.rds.id &&
      aws_vpc_security_group_egress_rule.provisionador_rds.from_port == 5432 &&
      aws_vpc_security_group_egress_rule.provisionador_rds.to_port == 5432
    )
    error_message = "A Lambda deve ter saída 5432 para o security group do RDS."
  }

  assert {
    condition = (
      aws_lambda_function.provisionador.environment[0].variables.ADMIN_SECRET_ARN == aws_secretsmanager_secret.db_credentials.arn &&
      aws_lambda_function.provisionador.environment[0].variables.DB_NAME_CADASTROS == "autoreparos_db"
    )
    error_message = "A Lambda deve receber o ARN da credencial admin e o nome da database do Cadastros."
  }
}

run "function_url_aws_iam_so_para_as_roles_de_deploy" {
  command = apply

  assert {
    condition     = aws_lambda_function_url.provisionador.authorization_type == "AWS_IAM"
    error_message = "A Function URL deve exigir AuthType AWS_IAM."
  }

  assert {
    condition     = aws_lambda_function_url.provisionador.function_name == aws_lambda_function.provisionador.function_name
    error_message = "A Function URL deve apontar para o provisionador."
  }

  assert {
    condition = (
      toset([for p in aws_lambda_permission.provisionador_url : p.principal]) == toset([for s in ["os", "cobranca", "execucao", "cadastros"] : "arn:aws:iam::198903849859:role/autoreparos-deploy-${s}"]) &&
      alltrue([for p in aws_lambda_permission.provisionador_url : p.action == "lambda:InvokeFunctionUrl" && p.function_url_auth_type == "AWS_IAM"])
    )
    error_message = "lambda:InvokeFunctionUrl deve ser permitido só às 4 roles autoreparos-deploy-<servico>."
  }

  assert {
    condition = (
      toset([for p in aws_lambda_permission.provisionador_invoke : p.principal]) == toset([for s in ["os", "cobranca", "execucao", "cadastros"] : "arn:aws:iam::198903849859:role/autoreparos-deploy-${s}"]) &&
      alltrue([for p in aws_lambda_permission.provisionador_invoke : p.action == "lambda:InvokeFunction" && p.invoked_via_function_url == true])
    )
    error_message = "lambda:InvokeFunction deve valer só pela Function URL e só para as 4 roles de deploy."
  }

  assert {
    condition = (
      aws_ssm_parameter.provisionador_url.name == "/autoreparos/production/provisionador-db/url" &&
      aws_ssm_parameter.provisionador_url.type == "String" &&
      aws_ssm_parameter.provisionador_url.value == aws_lambda_function_url.provisionador.function_url
    )
    error_message = "A Function URL deve ser publicada em /autoreparos/production/provisionador-db/url."
  }
}

run "unica_role_com_a_credencial_admin" {
  command = apply

  assert {
    condition     = jsondecode(aws_iam_role.provisionador.assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com"
    error_message = "A role do provisionador deve ser assumida só pelo serviço Lambda."
  }

  assert {
    condition = (
      aws_lambda_function.provisionador.role == aws_iam_role.provisionador.arn &&
      aws_iam_role_policy.provisionador_segredos.role == aws_iam_role.provisionador.id
    )
    error_message = "A política com a credencial admin deve estar na role de execução do provisionador."
  }

  assert {
    condition = anytrue([
      for st in jsondecode(aws_iam_role_policy.provisionador_segredos.policy).Statement :
      st.Effect == "Allow" && contains(st.Action, "secretsmanager:GetSecretValue") && contains(st.Resource, aws_secretsmanager_secret.db_credentials.arn)
    ])
    error_message = "O provisionador deve ler a credencial admin do RDS."
  }

  assert {
    condition = alltrue(flatten([
      for st in jsondecode(aws_iam_role_policy.provisionador_segredos.policy).Statement : [
        for r in st.Resource :
        r == aws_secretsmanager_secret.db_credentials.arn || r == "arn:aws:secretsmanager:us-east-1:198903849859:secret:autoreparos/production/*/database-??????"
      ]
    ]))
    error_message = "O provisionador só lê a credencial admin e os segredos autoreparos/production/<servico>/database."
  }

  # Nenhuma outra política declarada neste repositório concede ações do Secrets Manager (nem
  # curinga) ou anexa política gerenciada ampla: só a política do provisionador cita secretsmanager.
  assert {
    condition = [
      for f in sort(fileset(path.module, "*.{tf,json,tftpl}")) : f
      if length(regexall("\"secretsmanager:", file("${path.module}/${f}"))) > 0
      ] == ["provisionador.tf"] && length(regexall(
        "\"secretsmanager:", file("${path.module}/provisionador.tf")
    )) == 1
    error_message = "Só a política do provisionador pode conceder secretsmanager:* neste repositório."
  }

  assert {
    condition = length(flatten([
      for f in fileset(path.module, "*.{tf,json,tftpl}") :
      regexall("(AdministratorAccess|SecretsManagerReadWrite|PowerUserAccess|\"\\*\"\\s*\\])|(Action\\s*=\\s*\"\\*\")", file("${path.module}/${f}"))
    ])) == 0
    error_message = "Nenhuma role deste repositório pode ter ação curinga ou política gerenciada que leia segredos."
  }

  assert {
    condition = length(flatten([
      for f in fileset(path.module, "*.tf") :
      regexall("resource\\s+\"aws_iam_role\"", file("${path.module}/${f}"))
    ])) == 1
    error_message = "O provisionador deve ser a única role IAM declarada neste repositório."
  }
}
