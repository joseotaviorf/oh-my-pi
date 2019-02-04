DROP TABLE IF EXISTS public.bank_account;
CREATE TABLE public.bank_account (
  "id" BIGINT NOT NULL,
  "usuario_id" BIGINT,
  "atualizadoEm" TIMESTAMP,
  "criadoEm" TIMESTAMP
)
WITH (oids = false);
