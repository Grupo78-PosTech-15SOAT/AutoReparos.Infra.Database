-- =============================================================================
-- AUTO REPAROS - DDL DE INICIALIZAÇÃO DE SCHEMA (POSTGRESQL 16) - [DOCUMENTAL]
-- =============================================================================
-- AVISO ARQUITETURAL IMPORTANTE:
-- O Entity Framework Core (EF Core Migrations), localizado no repositório
-- AutoReparos.App (projeto AutoReparos.Infra), é a ÚNICA FONTE DA VERDADE para
-- o schema, versionamento e evolução estrutural do banco de dados da aplicação.
-- 
-- Este script SQL tem finalidade estritamente DOCUMENTAL, de auditoria e de
-- referência técnica da arquitetura relacional 3NF.
-- 
-- RISCO ARQUITETURAL: BAIXO (NÃO ZERO)
-- A existência de scripts DDL manuais paralelos ao EF Core apresenta risco
-- baixo de divergência cadastral (drift) se mantidos sem sincronização rigorosa
-- com o AppDbContextModelSnapshot.cs. Portanto, em ambientes de execução integrados
-- com a aplicação, as migrações devem ser aplicadas EXCLUSIVAMENTE via EF Core
-- (ou bundle de migrações gerado pelo dotnet ef).
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -----------------------------------------------------------------------------
-- 1. Tabela Clientes
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "Clientes" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "Nome" VARCHAR(100) NOT NULL,
    "Documento" VARCHAR(14) NOT NULL,
    "TipoDocumento" INTEGER NOT NULL, -- 0 = Fisica (CPF), 1 = Juridica (CNPJ)
    "Email" VARCHAR(200) NOT NULL,
    "Telefone" VARCHAR(16) NOT NULL,
    "CriadoEm" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "AtualizadoEm" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "InativoEm" TIMESTAMP WITH TIME ZONE NULL,
    CONSTRAINT "UQ_Clientes_Documento" UNIQUE ("Documento"),
    CONSTRAINT "UQ_Clientes_Email" UNIQUE ("Email"),
    CONSTRAINT "UQ_Clientes_Telefone" UNIQUE ("Telefone")
);

-- -----------------------------------------------------------------------------
-- 2. Tabela Veiculos
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "Veiculos" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "ClienteId" UUID NOT NULL,
    "Marca" VARCHAR(50) NOT NULL,
    "Modelo" VARCHAR(50) NOT NULL,
    "AnoFabricacao" INTEGER NOT NULL,
    "AnoModelo" INTEGER NOT NULL,
    "Placa" VARCHAR(7) NOT NULL,
    "Chassi" VARCHAR(17) NOT NULL,
    "Renavam" VARCHAR(11) NOT NULL,
    "CriadoEm" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "AtualizadoEm" TIMESTAMP WITH TIME ZONE NULL,
    CONSTRAINT "FK_Veiculos_Clientes_ClienteId" FOREIGN KEY ("ClienteId") REFERENCES "Clientes"("Id") ON DELETE RESTRICT,
    CONSTRAINT "UQ_Veiculos_Placa" UNIQUE ("Placa"),
    CONSTRAINT "UQ_Veiculos_Chassi" UNIQUE ("Chassi"),
    CONSTRAINT "UQ_Veiculos_Renavam" UNIQUE ("Renavam")
);

-- -----------------------------------------------------------------------------
-- 3. Tabela Servicos (Catálogo de Serviços / Mão de Obra)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "Servicos" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "Nome" VARCHAR(100) NOT NULL,
    "Descricao" VARCHAR(500) NULL,
    "ValorTabelado" NUMERIC(18, 2) NULL,
    "CriadoEm" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "AtualizadoEm" TIMESTAMP WITH TIME ZONE NULL
);

-- -----------------------------------------------------------------------------
-- 4. Tabela Insumos (Peças e Materiais de Estoque)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "Insumos" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "Nome" VARCHAR(100) NOT NULL,
    "Descricao" VARCHAR(500) NULL,
    "Valor" NUMERIC(18, 2) NOT NULL,
    "QuantidadeEstoque" INTEGER NOT NULL DEFAULT 0,
    "CriadoEm" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "AtualizadoEm" TIMESTAMP WITH TIME ZONE NULL
);

-- -----------------------------------------------------------------------------
-- 5. Tabela OrdensServico (Fato Principal da Oficina)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "OrdensServico" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "ClienteId" UUID NOT NULL,
    "VeiculoId" UUID NOT NULL,
    "Status" INTEGER NOT NULL DEFAULT 0, -- 0=Recebida, 1=EmDiagnostico, 2=AguardandoAprovacao, 3=EmExecucao, 4=Finalizada, 5=Entregue
    "Observacao" VARCHAR(500) NULL,
    "ResponsavelId" VARCHAR(450) NULL,
    "CriadoEm" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "DiagnosticoIniciadoEm" TIMESTAMP WITH TIME ZONE NULL,
    "EnvioAprovacaoEm" TIMESTAMP WITH TIME ZONE NULL,
    "IniciadoEm" TIMESTAMP WITH TIME ZONE NULL,
    "FinalizadoEm" TIMESTAMP WITH TIME ZONE NULL,
    "EntregueEm" TIMESTAMP WITH TIME ZONE NULL,
    CONSTRAINT "FK_OrdensServico_Clientes_ClienteId" FOREIGN KEY ("ClienteId") REFERENCES "Clientes"("Id") ON DELETE RESTRICT,
    CONSTRAINT "FK_OrdensServico_Veiculos_VeiculoId" FOREIGN KEY ("VeiculoId") REFERENCES "Veiculos"("Id") ON DELETE RESTRICT
);

-- -----------------------------------------------------------------------------
-- 6. Tabela OrdensServicoServicos (Associativa Ordem de Serviço - Serviços)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "OrdensServicoServicos" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "OrdemServicoId" UUID NOT NULL,
    "ServicoId" UUID NOT NULL,
    "ValorCobrado" NUMERIC(18, 2) NOT NULL,
    "Status" INTEGER NOT NULL DEFAULT 0, -- 0=Pendente, 1=EmExecucao, 2=Concluido
    "IniciadoEm" TIMESTAMP WITH TIME ZONE NULL,
    "ConcluidoEm" TIMESTAMP WITH TIME ZONE NULL,
    CONSTRAINT "FK_OrdensServicoServicos_OrdensServico_OrdemServicoId" FOREIGN KEY ("OrdemServicoId") REFERENCES "OrdensServico"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_OrdensServicoServicos_Servicos_ServicoId" FOREIGN KEY ("ServicoId") REFERENCES "Servicos"("Id") ON DELETE RESTRICT
);

-- -----------------------------------------------------------------------------
-- 7. Tabela OrdensServicoInsumos (Associativa Ordem de Serviço - Insumos)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "OrdensServicoInsumos" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "OrdemServicoId" UUID NOT NULL,
    "InsumoId" UUID NULL,
    "Descricao" VARCHAR(200) NOT NULL,
    "Quantidade" INTEGER NOT NULL,
    "ValorUnitario" NUMERIC(18, 2) NOT NULL,
    "Origem" INTEGER NOT NULL DEFAULT 0, -- 0=Estoque, 1=Externo
    CONSTRAINT "FK_OrdensServicoInsumos_OrdensServico_OrdemServicoId" FOREIGN KEY ("OrdemServicoId") REFERENCES "OrdensServico"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_OrdensServicoInsumos_Insumos_InsumoId" FOREIGN KEY ("InsumoId") REFERENCES "Insumos"("Id") ON DELETE RESTRICT
);

-- -----------------------------------------------------------------------------
-- 8. Tabelas de Identidade e Acesso (ASP.NET Core Identity com UUID)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "AspNetRoles" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "Name" VARCHAR(256) NULL,
    "NormalizedName" VARCHAR(256) NULL,
    "ConcurrencyStamp" TEXT NULL,
    CONSTRAINT "RoleNameIndex" UNIQUE ("NormalizedName")
);

CREATE TABLE IF NOT EXISTS "AspNetUsers" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "NomeCompleto" VARCHAR(150) NOT NULL,
    "Tipo" INTEGER NOT NULL, -- 0=Administrador, 1=Atendente, 2=Mecanico, 3=Cliente
    "UserName" VARCHAR(256) NULL,
    "NormalizedUserName" VARCHAR(256) NULL,
    "Email" VARCHAR(256) NULL,
    "NormalizedEmail" VARCHAR(256) NULL,
    "EmailConfirmed" BOOLEAN NOT NULL DEFAULT FALSE,
    "PasswordHash" TEXT NOT NULL,
    "SecurityStamp" TEXT NULL,
    "ConcurrencyStamp" TEXT NULL,
    "PhoneNumber" TEXT NULL,
    "PhoneNumberConfirmed" BOOLEAN NOT NULL DEFAULT FALSE,
    "TwoFactorEnabled" BOOLEAN NOT NULL DEFAULT FALSE,
    "LockoutEnd" TIMESTAMP WITH TIME ZONE NULL,
    "LockoutEnabled" BOOLEAN NOT NULL DEFAULT FALSE,
    "AccessFailedCount" INTEGER NOT NULL DEFAULT 0,
    "CriadoEm" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "AtualizadoEm" TIMESTAMP WITH TIME ZONE NULL,
    CONSTRAINT "UserNameIndex" UNIQUE ("NormalizedUserName")
);

CREATE TABLE IF NOT EXISTS "AspNetRoleClaims" (
    "Id" INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    "RoleId" UUID NOT NULL,
    "ClaimType" TEXT NULL,
    "ClaimValue" TEXT NULL,
    CONSTRAINT "FK_AspNetRoleClaims_AspNetRoles_RoleId" FOREIGN KEY ("RoleId") REFERENCES "AspNetRoles"("Id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "AspNetUserClaims" (
    "Id" INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    "UserId" UUID NOT NULL,
    "ClaimType" TEXT NULL,
    "ClaimValue" TEXT NULL,
    CONSTRAINT "FK_AspNetUserClaims_AspNetUsers_UserId" FOREIGN KEY ("UserId") REFERENCES "AspNetUsers"("Id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "AspNetUserLogins" (
    "LoginProvider" TEXT NOT NULL,
    "ProviderKey" TEXT NOT NULL,
    "ProviderDisplayName" TEXT NULL,
    "UserId" UUID NOT NULL,
    PRIMARY KEY ("LoginProvider", "ProviderKey"),
    CONSTRAINT "FK_AspNetUserLogins_AspNetUsers_UserId" FOREIGN KEY ("UserId") REFERENCES "AspNetUsers"("Id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "AspNetUserRoles" (
    "UserId" UUID NOT NULL,
    "RoleId" UUID NOT NULL,
    PRIMARY KEY ("UserId", "RoleId"),
    CONSTRAINT "FK_AspNetUserRoles_AspNetRoles_RoleId" FOREIGN KEY ("RoleId") REFERENCES "AspNetRoles"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_AspNetUserRoles_AspNetUsers_UserId" FOREIGN KEY ("UserId") REFERENCES "AspNetUsers"("Id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "AspNetUserTokens" (
    "UserId" UUID NOT NULL,
    "LoginProvider" TEXT NOT NULL,
    "Name" TEXT NOT NULL,
    "Value" TEXT NULL,
    PRIMARY KEY ("UserId", "LoginProvider", "Name"),
    CONSTRAINT "FK_AspNetUserTokens_AspNetUsers_UserId" FOREIGN KEY ("UserId") REFERENCES "AspNetUsers"("Id") ON DELETE CASCADE
);
