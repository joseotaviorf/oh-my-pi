drop table if exists polygon_region;

create table polygon_region (
  id bigint not null,
  poligono varchar,
  regiao_id bigint not null,
  atualizadoEm timestamp,
  criadoEm timestamp,
  dt_timestamp timestamp
  CONSTRAINT polygon_region_pkey PRIMARY KEY(id)
);
