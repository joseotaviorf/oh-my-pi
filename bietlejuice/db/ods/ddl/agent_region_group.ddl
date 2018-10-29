DROP TABLE IF EXISTS agent_region_group;
CREATE TABLE agent_region_group (
  "dt" DATE NOT NULL,
  "dadosagente_id" bigint NOT NULL,
  "regioes" VARCHAR NOT NULL,
  "area" VARCHAR NOT NULL,
  "secondary_area" VARCHAR NULL,
  "area_deprecated" VARCHAR NULL,
  "secondary_area_deprecated" VARCHAR NULL,
  PRIMARY KEY ("dt","dadosagente_id","area")
)