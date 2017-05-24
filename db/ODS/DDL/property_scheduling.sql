DROP TABLE IF EXISTS public.property_scheduling;
CREATE TABLE public.property_scheduling (
  id_property_scheduling BIGINT,
  id_imovel INTEGER NOT NULL,
  id_scheduling INTEGER,
  id_owner INTEGER,
  id_user_affiliate INTEGER,
  id_user_agent INTEGER,
  id_user_visitor INTEGER,
  id_user_visit_agent INTEGER,
  id_visit INTEGER,
  visit_created_from_app INTEGER,
  visit_created_type VARCHAR(14),
  visit_last_updated_from_app INTEGER,
  visit_last_updated_type VARCHAR(14),
  id_rental_flow INTEGER,
  id_negotiation INTEGER,
  dt_negotiation TIMESTAMP,
  id_pre_proposal INTEGER,
  id_proposal INTEGER,
  id_contract INTEGER,
  dt_contract_anullment DATE
)
WITH (oids = false);
