drop table if exists user_affiliate;
create table if not exists user_affiliate (
    id bigint not null,
    inicioAtuacao timestamp,
    tipoAfiliado varchar(255),
    cidadeAtuacao varchar(255),
    ativo boolean,
    atualizadoEm timestamp,
    criadoEm timestamp,
    numeroCreci varchar(255),
    origin varchar(255),
    affiliateType varchar(255),
    user_id bigint
);