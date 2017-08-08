DROP TABLE IF EXISTS public.pre_proposal;
CREATE TABLE public.pre_proposal (
  id INTEGER NOT NULL,
  "aceitoAluguel" INTEGER,
  "aceitoComprovarRenda" INTEGER,
  "aceitoEncargos" INTEGER,
  aluguel INTEGER,
  "aluguelOriginal" INTEGER,
  "condominioOriginal" INTEGER,
  -- "iptuOriginal" integer,
  "dataAprovacao" public.datetime,
  edicao VARCHAR(50) NOT NULL,
  status VARCHAR(50) NOT NULL,
  "proprietarioAceitouCondicoes5A" INTEGER,
  usuario_id BIGINT,
  imovel_id BIGINT,
  "criadoEm" public.datetime,
  "atualizadoEm" public.datetime,
  "ultimoUpdateEdicao" INTEGER,
  "dataPrimerioEnvio" public.datetime,
  code varchar(10),
  rejection_reason varchar(255),
  animais_condition INTEGER,
  quando_vai_mudar_condition INTEGER,
  quem_vai_morar_condition INTEGER,
  special_conditions_count INTEGER,
  remove_conditions INTEGER,
  include_conditions INTEGER,
  maintenance_or_repair_conditions INTEGER,
  replace_or_modify_conditions INTEGER,
  other_conditions INTEGER
)
WITH (oids = false);

-- select * from pre_proposal


