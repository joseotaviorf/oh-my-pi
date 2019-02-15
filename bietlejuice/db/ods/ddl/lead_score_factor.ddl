DROP TABLE IF EXISTS public.lead_score_factor;
CREATE TABLE lead_score_factor (
  lead_id bigint NOT NULL,
  score_factor bigint NULL
) WITH (oids = false);
