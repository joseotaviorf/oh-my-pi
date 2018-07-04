DROP TABLE IF EXISTS public.dim_agent_region ;
CREATE TABLE public.dim_agent_region (
  sk_agentregion BIGINT,
  sk_regions_date INTEGER,
  sk_agent INTEGER,
  regions VARCHAR(512),
  area VARCHAR(10),
  secondary_area VARCHAR(10) NULL,
  CONSTRAINT dim_agent_region_pkey PRIMARY KEY(sk_agentregion)
);