DROP TABLE if exists public.reprocessed_lead;

CREATE TABLE public.reprocessed_lead
(
  id bigint,
  id_origin_lead bigint
)
WITH (
  OIDS=FALSE
)