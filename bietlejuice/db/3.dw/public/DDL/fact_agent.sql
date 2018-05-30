DROP TABLE IF EXISTS public.fact_agent ;
CREATE TABLE public.fact_agent (
  sk_agent_id VARCHAR,
  sk_date VARCHAR(8),
  available_slots INTEGER,
  total_slots INTEGER,
  area VARCHAR(10),
  sk_agentregiongroup_id VARCHAR(20)
);