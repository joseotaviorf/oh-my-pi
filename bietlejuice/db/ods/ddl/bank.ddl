DROP TABLE public.bank;
CREATE TABLE public.bank (
  "id" BIGINT NOT NULL,
  "atualizadoEm" TIMESTAMP,
  "criadoEm" TIMESTAMP,
  "codigo" VARCHAR(255),
  "nome" VARCHAR(255),
  "nomeFebraban" VARCHAR(255),
  "featuredRank" INTEGER
)
WITH (oids = false);
