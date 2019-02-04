DROP TABLE IF EXISTS public.bank_transaction;
CREATE TABLE public.bank_transaction (
  "id" BIGINT NOT NULL,
  "dataCriacao" TIMESTAMP,
  "descricao" VARCHAR(255),
  "tipo" VARCHAR(255),
  "valor" NUMERIC(22,2),
  "contaCorrente_id" INTEGER,
  "dataOperacao" TIMESTAMP,
  "imovel_id" BIGINT,
  "atualizadoEm" TIMESTAMP,
  "despesa_id" BIGINT,
  "paymentDate" TIMESTAMP,
  "leadCampaign_id" INTEGER
)
WITH (oids = false);
