drop table if exists public.affiliate_payments;

create table public.affiliate_payments (
    id  integer NULL,
    tipo varchar(255) NULL,
    valor decimal(14,4) NULL,
    imovel_id  varchar(255) NULL,
    conta_corrente_id integer NULL,
    creation_date timestamp NULL,
    payment_date timestamp NULL
);
