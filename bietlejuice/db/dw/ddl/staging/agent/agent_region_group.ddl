DROP TABLE IF EXISTS staging.agent_region_group;
CREATE TABLE staging.agent_region_group (
  "dt" DATE NOT NULL,
  "dadosagente_id" bigint NOT NULL,
  "regioes" VARCHAR(3076) NOT NULL,
  "area" VARCHAR NULL,
  "secondary_area" VARCHAR NULL,
  "area_deprecated" VARCHAR NULL,
  "secondary_area_deprecated" VARCHAR NULL
)