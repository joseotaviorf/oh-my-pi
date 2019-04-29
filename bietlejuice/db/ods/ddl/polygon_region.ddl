drop table if exists polygon_region;
create table if not exists polygon_region (
  id bigint primary key,
  poligono varchar,
  regiao_id bigint not null,
  atualizadoEm timestamp,
  criadoEm timestamp,
  dt_timestamp timestamp
);
