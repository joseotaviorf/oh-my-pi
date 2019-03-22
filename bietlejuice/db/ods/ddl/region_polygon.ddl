drop table if exists region_polygon;

create table region_polygon (
  id bigint not null,
  poligono varchar,
  regiao_id bigint not null,
  atualizadoEm timestamp,
  criadoEm timestamp,
  dt_timestamp timestamp
  CONSTRAINT region_polygon_pkey PRIMARY KEY(id)
);
