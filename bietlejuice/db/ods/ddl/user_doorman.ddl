DROP TABLE if exists public.user_doorman;

CREATE TABLE public.user_doorman
(
id bigint NOT NULL,
workAddress varchar(512),
workStreet varchar(512),
workHouseNumber varchar(56),
workNeighbourhood varchar(255),
workCity varchar(255),
workState varchar(255),
lat double,
lng double,
placeId integer,
code varchar(255),
recruiter varchar(255),
subscriptionSource varchar(56),
doorman_occupation_id integer,
occupation_name varchar(255),
atualizadoEm timestamp,
criadoEm timestamp,
joinedProgramAt timestamp,
id_dados_afiliado bigint,
is_active boolean
)
WITH (
  OIDS=FALSE
);