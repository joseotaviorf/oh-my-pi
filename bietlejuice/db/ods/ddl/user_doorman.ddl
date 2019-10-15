drop table if exists public.user_doorman;
create table public.user_doorman (
    id bigint not null,
    workaddress varchar(512),
    workstreet varchar(512),
    workhousenumber integer,
    workneighbourhood varchar(255),
    workcity varchar(255),
    workstate varchar(255),
    lat decimal,
    lng decimal,
    placeid varchar(255),
    recruiter varchar(255),
    subscriptionsource varchar(255),
    doorman_occupation_id integer,
    occupation_name varchar(255),
    atualizadoem timestamp,
    criadoem timestamp,
    joinedprogramat timestamp,
    id_dados_afiliado bigint,
    is_active boolean
);