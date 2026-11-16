"""Provisionador da database de cada serviço (D-54, door 9 de deploy-servicos).

Function URL com AuthType AWS_IAM. O serviço é deduzido da role que assinou a chamada
(`autoreparos-deploy-<servico>`); qualquer outro chamador recebe 403 antes de qualquer leitura
de segredo ou conexão com o banco. Cria, de forma idempotente, o usuário `<servico>_app` com a
senha do segredo `autoreparos/<ambiente>/<servico>/database` e a database `<servico>_db` com esse
dono. O Cadastros usa a database existente (D-34), que passa a ter `cadastros_app` como dono.
"""

import json
import logging
import os
import re

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SERVICOS = ("os", "cobranca", "execucao", "cadastros")
CONTA_PADRAO = "198903849859"
_ARN_DEPLOY = re.compile(
    r"arn:aws:sts::(?P<conta>\d{12}):assumed-role/autoreparos-deploy-(?P<servico>[a-z]+)/[^/]+"
)


class Recusado(Exception):
    def __init__(self, status, mensagem):
        super().__init__(mensagem)
        self.status = status
        self.mensagem = mensagem


def identificador(nome):
    """Cita um identificador do PostgreSQL (nome de role ou database)."""
    if not nome or "\x00" in nome:
        raise ValueError("identificador inválido")
    return '"' + nome.replace('"', '""') + '"'


def literal(texto):
    """Cita um literal de texto do PostgreSQL; CREATE ROLE não aceita parâmetro ligado."""
    if "\x00" in texto:
        raise ValueError("literal inválido")
    if "\\" in texto:
        return "E'" + texto.replace("\\", "\\\\").replace("'", "''") + "'"
    return "'" + texto.replace("'", "''") + "'"


def servico_da_chamada(evento, conta):
    """Devolve o serviço da role de deploy que assinou a chamada, ou None."""
    contexto = evento.get("requestContext") if isinstance(evento, dict) else None
    autorizador = (contexto or {}).get("authorizer") or {}
    iam = autorizador.get("iam") or {}
    user_arn = iam.get("userArn")
    if not isinstance(user_arn, str):
        return None
    m = _ARN_DEPLOY.fullmatch(user_arn)
    if not m or m.group("conta") != conta or m.group("servico") not in SERVICOS:
        return None
    return m.group("servico")


def _resposta(status, corpo):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(corpo, ensure_ascii=False),
    }


def _ler_segredo(secrets, segredo_id):
    valor = secrets.get_secret_value(SecretId=segredo_id)
    return json.loads(valor["SecretString"])


def _consultar(cursor, sql, params):
    cursor.execute(sql, params)
    return cursor.fetchone()


def provisionar(conexao, database, usuario, senha, criar_database):
    """Cria usuário e database se não existem. Nunca troca a senha de um usuário existente."""
    conexao.autocommit = True  # CREATE DATABASE não roda dentro de transação
    cursor = conexao.cursor()
    try:
        criado_usuario = False
        if _consultar(cursor, "SELECT 1 FROM pg_roles WHERE rolname = %s", (usuario,)) is None:
            cursor.execute(f"CREATE ROLE {identificador(usuario)} WITH LOGIN PASSWORD {literal(senha)}")
            criado_usuario = True
        # O admin do RDS não é superusuário: para dar a database a outro dono precisa poder
        # assumir esse papel (PostgreSQL 16).
        cursor.execute(f"GRANT {identificador(usuario)} TO CURRENT_USER")

        dono = _consultar(
            cursor, "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = %s", (database,)
        )
        criado_database = False
        if dono is None:
            if not criar_database:
                raise Recusado(409, f"database {database} não existe")
            cursor.execute(f"CREATE DATABASE {identificador(database)} OWNER {identificador(usuario)}")
            cursor.execute(f"REVOKE ALL ON DATABASE {identificador(database)} FROM PUBLIC")
            criado_database = True
        elif dono[0] != usuario:
            cursor.execute(f"ALTER DATABASE {identificador(database)} OWNER TO {identificador(usuario)}")
        return {"database": criado_database, "usuario": criado_usuario}
    finally:
        cursor.close()


def processar(evento, secrets, conectar, config):
    conta = config.get("CONTA_AWS") or CONTA_PADRAO
    servico = servico_da_chamada(evento, conta)
    if servico is None:
        logger.warning("chamada recusada: chamador não é uma role autoreparos-deploy-<servico>")
        return _resposta(403, {"erro": "chamador não autorizado"})

    metodo = ((evento.get("requestContext") or {}).get("http") or {}).get("method", "POST")
    if metodo != "POST":
        return _resposta(405, {"erro": "use POST"})

    ambiente = config.get("AMBIENTE") or "production"
    if servico == "cadastros":
        database, criar_database = config.get("DB_NAME_CADASTROS") or "autoreparos_db", False
    else:
        database, criar_database = f"{servico}_db", True
    usuario = f"{servico}_app"

    try:
        admin = _ler_segredo(secrets, config["ADMIN_SECRET_ARN"])
        segredo_id = f"autoreparos/{ambiente}/{servico}/database"
        try:
            segredo = _ler_segredo(secrets, segredo_id)
        except Exception:
            logger.exception("segredo %s indisponível", segredo_id)
            raise Recusado(409, f"segredo {segredo_id} ausente ou ilegível")
        if segredo.get("username") != usuario or segredo.get("dbname") != database:
            raise Recusado(409, f"segredo {segredo_id} deve ter username {usuario} e dbname {database}")
        senha = segredo.get("password")
        if not isinstance(senha, str) or not senha:
            raise Recusado(409, f"segredo {segredo_id} sem password")

        conexao = conectar(
            host=admin["host"],
            port=int(admin.get("port", 5432)),
            database=admin.get("dbname") or "postgres",
            user=admin["username"],
            password=admin["password"],
        )
        try:
            criado = provisionar(conexao, database, usuario, senha, criar_database)
        finally:
            conexao.close()
    except Recusado as recusa:
        logger.warning("provisionamento de %s recusado: %s", servico, recusa.mensagem)
        return _resposta(recusa.status, {"erro": recusa.mensagem})
    except Exception:
        logger.exception("falha ao provisionar a database de %s", servico)
        return _resposta(500, {"erro": "falha ao provisionar a database"})

    logger.info("servico=%s database=%s usuario=%s criado=%s", servico, database, usuario, criado)
    return _resposta(
        200, {"servico": servico, "database": database, "usuario": usuario, "criado": criado}
    )


def _conectar_postgres(**kwargs):
    import ssl

    import pg8000.dbapi

    ca = os.environ.get("DB_SSL_CA")
    if ca:
        contexto = ssl.create_default_context(cafile=ca)
    else:
        # Mesmo nível do segredo admin (`SSL Mode=Prefer`): cifrado, sem validar o certificado.
        contexto = ssl.create_default_context()
        contexto.check_hostname = False
        contexto.verify_mode = ssl.CERT_NONE
    return pg8000.dbapi.connect(ssl_context=contexto, timeout=10, **kwargs)


_secrets = None


def handler(evento, contexto):
    global _secrets
    if _secrets is None:
        import boto3

        _secrets = boto3.client("secretsmanager")
    return processar(evento, _secrets, _conectar_postgres, os.environ)
