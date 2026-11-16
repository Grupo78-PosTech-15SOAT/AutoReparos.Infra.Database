"""Provas do C29: o provisionador cria só a database e o usuário da role que assinou a chamada.

Roda sem banco e sem AWS: o conector do Postgres e o cliente do Secrets Manager são falsos.
Uso, da raiz do pai:
    python3 -m unittest discover -s submodules/AutoReparos.Infra.Database/lambda/provisionador/tests -p test_provisionador.py
"""

import json
import logging
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import provisionador  # noqa: E402

logging.disable(logging.CRITICAL)

CONTA = "198903849859"
ADMIN_ARN = f"arn:aws:secretsmanager:us-east-1:{CONTA}:secret:autoreparos/production/database/credentials-AbCdEf"
ADMIN = {
    "username": "autoreparos_admin",
    "password": "senha-do-admin",
    "dbname": "autoreparos_db",
    "host": "autoreparos-rds-production.abc.us-east-1.rds.amazonaws.com",
    "port": 5432,
}
CONFIG = {
    "ADMIN_SECRET_ARN": ADMIN_ARN,
    "AMBIENTE": "production",
    "DB_NAME_CADASTROS": "autoreparos_db",
    "CONTA_AWS": CONTA,
}
SERVICOS = ("os", "cobranca", "execucao", "cadastros")


def evento(user_arn=None, metodo="POST"):
    contexto = {"http": {"method": metodo}}
    if user_arn is not None:
        contexto["authorizer"] = {"iam": {"userArn": user_arn, "accountId": CONTA}}
    return {"version": "2.0", "requestContext": contexto, "body": "{}"}


def arn_deploy(servico, sessao="GitHubActions"):
    return f"arn:aws:sts::{CONTA}:assumed-role/autoreparos-deploy-{servico}/{sessao}"


class SegredoAusente(Exception):
    pass


class SecretsFalso:
    def __init__(self):
        self.segredos = {ADMIN_ARN: dict(ADMIN)}
        for servico in SERVICOS:
            dbname = "autoreparos_db" if servico == "cadastros" else f"{servico}_db"
            self.segredos[f"autoreparos/production/{servico}/database"] = {
                "username": f"{servico}_app",
                "password": f"senha-do-{servico}",
                "dbname": dbname,
                "host": ADMIN["host"],
                "port": 5432,
            }
        self.lidos = []

    def get_secret_value(self, SecretId):
        self.lidos.append(SecretId)
        if SecretId not in self.segredos:
            raise SegredoAusente(SecretId)
        return {"SecretString": json.dumps(self.segredos[SecretId])}


class BancoFalso:
    """Simula o catálogo do PostgreSQL só no que o provisionador consulta e altera."""

    IDENT = r'"((?:[^"]|"")+)"'

    def __init__(self):
        self.usuarios = {ADMIN["username"]: ADMIN["password"]}
        self.databases = {"postgres": "rdsadmin", "autoreparos_db": ADMIN["username"]}
        self.comandos = []
        self.conexoes = []

    def conectar(self, **kwargs):
        self.conexoes.append(kwargs)
        return ConexaoFalsa(self)

    @staticmethod
    def _nome(texto):
        return texto.replace('""', '"')

    def executar(self, conexao, sql, params):
        self.comandos.append(sql)
        texto = " ".join(sql.split())
        if re.fullmatch(r"SELECT 1 FROM pg_roles WHERE rolname = %s", texto):
            return [(1,)] if params[0] in self.usuarios else []
        if re.fullmatch(r"SELECT pg_get_userbyid\(datdba\) FROM pg_database WHERE datname = %s", texto):
            return [(self.databases[params[0]],)] if params[0] in self.databases else []
        m = re.fullmatch(rf"CREATE ROLE {self.IDENT} WITH LOGIN PASSWORD '((?:[^']|'')*)'", texto)
        if m:
            nome = self._nome(m.group(1))
            if nome in self.usuarios:
                raise RuntimeError(f'role "{nome}" already exists')
            self.usuarios[nome] = m.group(2).replace("''", "'")
            return []
        m = re.fullmatch(rf"ALTER (?:ROLE|USER) {self.IDENT} .*PASSWORD '((?:[^']|'')*)'.*", texto)
        if m:
            self.usuarios[self._nome(m.group(1))] = m.group(2).replace("''", "'")
            return []
        m = re.fullmatch(rf"CREATE DATABASE {self.IDENT} (?:WITH )?OWNER {self.IDENT}", texto)
        if m:
            if not conexao.autocommit:
                raise RuntimeError("CREATE DATABASE cannot run inside a transaction block")
            nome, dono = self._nome(m.group(1)), self._nome(m.group(2))
            if nome in self.databases:
                raise RuntimeError(f'database "{nome}" already exists')
            if dono not in self.usuarios:
                raise RuntimeError(f'role "{dono}" does not exist')
            self.databases[nome] = dono
            return []
        m = re.fullmatch(rf"ALTER DATABASE {self.IDENT} OWNER TO {self.IDENT}", texto)
        if m:
            self.databases[self._nome(m.group(1))] = self._nome(m.group(2))
            return []
        if re.fullmatch(rf"GRANT {self.IDENT} TO CURRENT_USER", texto):
            return []
        if re.fullmatch(rf"REVOKE ALL ON DATABASE {self.IDENT} FROM PUBLIC", texto):
            return []
        raise AssertionError(f"SQL inesperado no banco falso: {sql!r}")


class ConexaoFalsa:
    def __init__(self, banco):
        self.banco = banco
        self.autocommit = False

    def cursor(self):
        return CursorFalso(self)

    def close(self):
        pass


class CursorFalso:
    def __init__(self, conexao):
        self.conexao = conexao
        self.linhas = []

    def execute(self, sql, params=None):
        self.linhas = self.conexao.banco.executar(self.conexao, sql, params)

    def fetchone(self):
        return self.linhas[0] if self.linhas else None

    def close(self):
        pass


class ProvisionadorTest(unittest.TestCase):
    def setUp(self):
        self.banco = BancoFalso()
        self.secrets = SecretsFalso()

    def chamar(self, ev):
        resposta = provisionador.processar(ev, self.secrets, self.banco.conectar, CONFIG)
        corpo = json.loads(resposta["body"]) if resposta.get("body") else None
        return resposta["statusCode"], corpo

    def test_role_do_servico_cria_so_a_database_e_o_usuario_dele_com_a_senha_do_segredo(self):
        for servico in ("os", "cobranca", "execucao"):
            with self.subTest(servico=servico):
                self.setUp()
                status, corpo = self.chamar(evento(arn_deploy(servico)))

                self.assertEqual(status, 200)
                self.assertEqual(
                    corpo,
                    {
                        "servico": servico,
                        "database": f"{servico}_db",
                        "usuario": f"{servico}_app",
                        "criado": {"database": True, "usuario": True},
                    },
                )
                self.assertEqual(
                    self.banco.usuarios,
                    {ADMIN["username"]: ADMIN["password"], f"{servico}_app": f"senha-do-{servico}"},
                )
                self.assertEqual(
                    self.banco.databases,
                    {"postgres": "rdsadmin", "autoreparos_db": ADMIN["username"], f"{servico}_db": f"{servico}_app"},
                )
                self.assertEqual(
                    self.secrets.lidos, [ADMIN_ARN, f"autoreparos/production/{servico}/database"]
                )

    def test_role_do_cadastros_torna_cadastros_app_dono_da_autoreparos_db_sem_criar_database(self):
        status, corpo = self.chamar(evento(arn_deploy("cadastros")))

        self.assertEqual(status, 200)
        self.assertEqual(
            corpo,
            {
                "servico": "cadastros",
                "database": "autoreparos_db",
                "usuario": "cadastros_app",
                "criado": {"database": False, "usuario": True},
            },
        )
        self.assertEqual(self.banco.usuarios["cadastros_app"], "senha-do-cadastros")
        self.assertEqual(
            self.banco.databases, {"postgres": "rdsadmin", "autoreparos_db": "cadastros_app"}
        )

    def test_segunda_chamada_responde_sucesso_sem_recriar_nem_trocar_a_senha(self):
        for servico in SERVICOS:
            with self.subTest(servico=servico):
                self.setUp()
                self.assertEqual(self.chamar(evento(arn_deploy(servico)))[0], 200)
                usuarios, databases = dict(self.banco.usuarios), dict(self.banco.databases)
                self.secrets.segredos[f"autoreparos/production/{servico}/database"]["password"] = "senha-nova"
                comandos_antes = len(self.banco.comandos)

                status, corpo = self.chamar(evento(arn_deploy(servico, "OutraSessao")))

                self.assertEqual(status, 200)
                self.assertEqual(corpo["criado"], {"database": False, "usuario": False})
                self.assertEqual(self.banco.usuarios, usuarios)
                self.assertEqual(self.banco.usuarios[f"{servico}_app"], f"senha-do-{servico}")
                self.assertEqual(self.banco.databases, databases)
                segunda = " ".join(self.banco.comandos[comandos_antes:])
                self.assertNotIn("CREATE", segunda)
                self.assertNotIn("PASSWORD", segunda)

    def test_outra_role_ou_sem_assinatura_responde_403_sem_tocar_no_banco(self):
        chamadores = {
            "sem requestContext": {"version": "2.0", "body": "{}"},
            "sem authorizer": evento(None),
            "authorizer sem iam": {"version": "2.0", "requestContext": {"authorizer": {}}},
            "role do pai": evento(f"arn:aws:sts::{CONTA}:assumed-role/autoreparos-github-pai/GitHubActions"),
            "role de deploy do web": evento(arn_deploy("web")),
            "prefixo de outra role": evento(f"arn:aws:sts::{CONTA}:assumed-role/autoreparos-deploy-os-extra/s"),
            "outra conta": evento("arn:aws:sts::111111111111:assumed-role/autoreparos-deploy-os/s"),
            "usuario iam": evento(f"arn:aws:iam::{CONTA}:user/autoreparos-deploy-os"),
            "arn da role, nao da sessao": evento(f"arn:aws:iam::{CONTA}:role/autoreparos-deploy-os"),
            "sessao com barra": evento(f"arn:aws:sts::{CONTA}:assumed-role/autoreparos-deploy-os/a/../cobranca"),
            "servico em maiusculas": evento(arn_deploy("OS")),
        }
        for nome, ev in chamadores.items():
            with self.subTest(chamador=nome):
                self.setUp()
                status, _ = self.chamar(ev)

                self.assertEqual(status, 403)
                self.assertEqual(self.banco.conexoes, [])
                self.assertEqual(self.banco.comandos, [])
                self.assertEqual(self.secrets.lidos, [])

    def test_role_do_os_nunca_cria_cobranca_db(self):
        status, corpo = self.chamar(evento(arn_deploy("os")))
        self.assertEqual(status, 200)
        self.assertNotIn("cobranca_db", self.banco.databases)
        self.assertNotIn("cobranca_app", self.banco.usuarios)

        # Mesmo que o segredo do OS aponte para a database da Cobrança, o nome vem da role.
        self.setUp()
        segredo = self.secrets.segredos["autoreparos/production/os/database"]
        segredo["dbname"], segredo["username"] = "cobranca_db", "cobranca_app"

        status, _ = self.chamar(evento(arn_deploy("os")))

        self.assertNotEqual(status, 200)
        self.assertNotIn("cobranca_db", self.banco.databases)
        self.assertNotIn("cobranca_app", self.banco.usuarios)
        self.assertNotIn("cobranca", " ".join(self.banco.comandos))
        self.assertNotIn("autoreparos/production/cobranca/database", self.secrets.lidos)

    def test_create_database_roda_fora_de_transacao(self):
        status, _ = self.chamar(evento(arn_deploy("execucao")))

        self.assertEqual(status, 200)
        self.assertEqual(len(self.banco.conexoes), 1)
        conexao = self.banco.conexoes[0]
        self.assertEqual(conexao["user"], ADMIN["username"])
        self.assertEqual(conexao["password"], ADMIN["password"])
        self.assertEqual(conexao["host"], ADMIN["host"])

    def test_senha_com_aspas_e_citada_sem_quebrar_o_sql(self):
        self.secrets.segredos["autoreparos/production/os/database"]["password"] = "a'b; DROP ROLE x; --"

        status, _ = self.chamar(evento(arn_deploy("os")))

        self.assertEqual(status, 200)
        self.assertEqual(self.banco.usuarios["os_app"], "a'b; DROP ROLE x; --")


if __name__ == "__main__":
    unittest.main()
