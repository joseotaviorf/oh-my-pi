DROP TABLE IF EXISTS public.pre_proposal;
CREATE TABLE public.pre_proposal (
  id INTEGER NOT NULL,
  "aceitoAluguel" INTEGER,
  "aceitoComprovarRenda" INTEGER,
  "aceitoEncargos" INTEGER,
  aluguel INTEGER,
  "aluguelOriginal" INTEGER,
  "condominioOriginal" INTEGER,
  "dataAprovacao" INTEGER,
  edicao VARCHAR(50) NOT NULL,
  status VARCHAR(50) NOT NULL,
  "proprietarioAceitouCondicoes5A" INTEGER,
  usuario_id BIGINT,
  imovel_id BIGINT,
  "criadoEm" public.datetime,
  "atualizadoEm" public.datetime,
  "ultimoUpdateEdicao" INTEGER
)
WITH (oids = false);

-- select * from pre_proposal
 