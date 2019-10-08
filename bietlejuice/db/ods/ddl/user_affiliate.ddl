drop table if exists user_affiliate;
create table if not exists user_affiliate (
    id bigint not null,
    indicadoPor_id bigint,
    inicioAtuacao timestamp,
    tipoAfiliado varchar(255),
    ativo boolean,
    atualizadoEm timestamp,
    criadoEm timestamp,
    origin varchar(255),
    affiliateType varchar(255)
);