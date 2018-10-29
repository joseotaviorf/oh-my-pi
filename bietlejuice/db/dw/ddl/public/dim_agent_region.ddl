DROP TABLE IF EXISTS public.dim_agent_region ;
CREATE TABLE public.dim_agent_region (
  sk_agent_region BIGINT,
  sk_regions_date INTEGER,
  sk_agent INTEGER,
  regions VARCHAR(512),
  area VARCHAR(10),
  secondary_area VARCHAR(10) NULL,
  area_deprecated VARCHAR(10) NULL,
  secondary_area_deprecated VARCHAR(10) NULL,
  dt_timestamp TIMESTAMP default getdate(),
  CONSTRAINT dim_agent_region_pkey PRIMARY KEY(sk_agent_region)
);