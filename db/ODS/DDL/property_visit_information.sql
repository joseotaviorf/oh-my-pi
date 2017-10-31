drop table if exists public.property_visit_information;

create table public.property_visit_information (
    imovel_id  bigint NULL,
    informacoes_visita  varchar(255) NULL,
    dt_added timestamp NULL,
    dt_deleted timestamp NULL
);