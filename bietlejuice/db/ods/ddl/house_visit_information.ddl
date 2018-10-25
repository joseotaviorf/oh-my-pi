drop table if exists public.house_visit_information;

create table public.house_visit_information (
    imovel_id  bigint NULL,
    informacoes_visita  varchar(255) NULL,
    dt_added timestamp NULL,
    dt_deleted timestamp NULL
);