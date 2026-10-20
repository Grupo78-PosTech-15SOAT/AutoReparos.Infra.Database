-- =============================================================================
-- AUTO REPAROS - ÍNDICES E OTIMIZAÇÃO DE PERFORMANCE (POSTGRESQL 16) - [DOCUMENTAL]
-- =============================================================================
-- AVISO ARQUITETURAL IMPORTANTE:
-- Os índices primários, estrangeiros e únicos estruturais da aplicação já são
-- criados e mantidos automaticamente pelo Entity Framework Core (EF Core Migrations).
-- 
-- Este script reúne a relação de índices nativos do modelo e propõe índices
-- compostos complementares voltados para otimização de consultas de alto
-- volume (ex: Fila Kanban, ordenação por prioridade, busca por CPF e placa).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Índices Estruturais de Chaves Estrangeiras (Relações 1:N)
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS "IX_Veiculos_ClienteId" ON "Veiculos" ("ClienteId");
CREATE INDEX IF NOT EXISTS "IX_OrdensServico_ClienteId" ON "OrdensServico" ("ClienteId");
CREATE INDEX IF NOT EXISTS "IX_OrdensServico_VeiculoId" ON "OrdensServico" ("VeiculoId");
CREATE INDEX IF NOT EXISTS "IX_OrdensServicoServicos_OrdemServicoId" ON "OrdensServicoServicos" ("OrdemServicoId");
CREATE INDEX IF NOT EXISTS "IX_OrdensServicoServicos_ServicoId" ON "OrdensServicoServicos" ("ServicoId");
CREATE INDEX IF NOT EXISTS "IX_OrdensServicoInsumos_OrdemServicoId" ON "OrdensServicoInsumos" ("OrdemServicoId");
CREATE INDEX IF NOT EXISTS "IX_OrdensServicoInsumos_InsumoId" ON "OrdensServicoInsumos" ("InsumoId");

-- -----------------------------------------------------------------------------
-- 2. Índices de Otimização Operacional e Fila Kanban
-- -----------------------------------------------------------------------------
-- Otimiza a renderização do Quadro Kanban, ordenando ordens por status e antiguidade
CREATE INDEX IF NOT EXISTS "idx_ordens_servico_status_criado_em" 
ON "OrdensServico" ("Status", "CriadoEm" ASC);

-- Otimiza buscas de histórico de veículos e clientes combinados
CREATE INDEX IF NOT EXISTS "idx_ordens_servico_cliente_veiculo" 
ON "OrdensServico" ("ClienteId", "VeiculoId");

-- Otimiza a listagem de ordens de serviço atribuídas a um mecânico ou responsável
CREATE INDEX IF NOT EXISTS "idx_ordens_servico_responsavel" 
ON "OrdensServico" ("ResponsavelId") 
WHERE "ResponsavelId" IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 3. Índices de Pesquisa Textual e Catálogo
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS "idx_clientes_nome" ON "Clientes" ("Nome");
CREATE INDEX IF NOT EXISTS "idx_servicos_nome" ON "Servicos" ("Nome");
CREATE INDEX IF NOT EXISTS "idx_insumos_nome" ON "Insumos" ("Nome");

-- -----------------------------------------------------------------------------
-- 4. Índices de Identidade e Segurança (Identity)
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS "EmailIndex" ON "AspNetUsers" ("NormalizedEmail");
