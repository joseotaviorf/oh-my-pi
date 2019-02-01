DROP TABLE if exists public.user_doorman;

CREATE TABLE public.user_doorman
(
id bigint NOT NULL,
workAddress varchar(512),
workHouseNumber varchar(56),
workNeighbourhood varchar(255),
workCity varchar(255),
code varchar(255),
atualizadoEm timestamp,
criadoEm timestamp,
joinedProgramAt timestamp
)
WITH (
  OIDS=FALSE
);