DROP TABLE IF EXISTS staging.agent_region_group;
CREATE TABLE staging.agent_region_group (
  "dt" date not null,
  "dadosagente_id" bigint NOT NULL,
  "regioes" VARCHAR(512) NOT NULL,
  "area" VARCHAR NOT null,
  "secondary_area" VARCHAR NULL,
  PRIMARY KEY ("dt","dadosagente_id","area")
)