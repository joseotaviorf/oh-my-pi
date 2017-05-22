
DROP TABLE IF EXISTS  public.booking ;

CREATE TABLE public.booking (
  id INTEGER NOT NULL,
  data DATE NOT NULL,
  status VARCHAR(50) NOT NULL,
  tipo VARCHAR(50) NOT NULL,
  hash VARCHAR(100),
  confirmado VARCHAR(100),
  encerrado VARCHAR(100),
  "agenteFixo" VARCHAR(100),
  "fupVisita" VARCHAR(100),
  "dataFupVisita" TIMESTAMP,
  "reagendadoDe_id" integer,
  visitante_id bigint,
  visita_id bigint,
  imovel_id bigint,
  agente_id bigint,
  atendente_id bigint,
  "fluxoLocacao_id" bigint,
  "criadoEm" TIMESTAMP WITHOUT TIME ZONE,
  "atualizadoEm" TIMESTAMP WITHOUT TIME ZONE,
  "slotDia" integer
)
WITH (oids = false);
