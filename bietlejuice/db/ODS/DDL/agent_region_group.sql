DROP TABLE IF EXISTS agent_region_group;
CREATE TABLE agent_region_group (
  "dt" date not null,
  "dadosagente_id" bigint NOT NULL,
  "regioes" VARCHAR NOT NULL,
  "area" VARCHAR NOT null,
  PRIMARY KEY ("dt","dadosagente_id","area")
)