DROP TABLE IF EXISTS agent_region_group;
CREATE TABLE agent_region_group (
  "dt" DATE NOT NULL,
  "dadosagente_id" bigint NOT NULL,
  "regioes" VARCHAR NOT NULL,
  "area" VARCHAR NOT NULL,
  "secondary_area" VARCHAR NULL,
  "new_area" VARCHAR NOT NULL,
  "new_secondary_area" VARCHAR NULL,
  PRIMARY KEY ("dt","dadosagente_id","area")
)