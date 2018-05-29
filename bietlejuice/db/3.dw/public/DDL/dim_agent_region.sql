drop table if exists public.dim_agent_region ;
CREATE TABLE public.dim_agent_region (
  sk_agentregiongroup_id BIGINT,
  sk_date INTEGER,
  sk_dadosagente_id INTEGER,
  regions VARCHAR(500),
  area VARCHAR(10),
  secondary_area VARCHAR(10) NULL,
  CONSTRAINT dim_agent_region_pkey PRIMARY KEY(sk_agentregiongroup_id)
);