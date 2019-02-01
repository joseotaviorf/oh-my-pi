DROP TABLE if exists public.user_affiliate;

CREATE TABLE public.user_affiliate
(
id bigint NOT NULL,
inicioAtuacao timestamp,
tipoAfiliado varchar(62),
cidadeAtuacao varchar(255),
ativo boolean,
atualizadoEm timestamp,
criadoEm timestamp,
numeroCreci varchar(24),
origin varchar(24),
affiliateType varchar(62),
user_id bigint
)
WITH (
  OIDS=FALSE
);