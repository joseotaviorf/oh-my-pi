DROP TABLE IF EXISTS public.dim_visit;
CREATE TABLE public.dim_visit (
  sk_visit INTEGER,
  id_visit INTEGER,
  cd_visit VARCHAR(200),
  day_visit DATE,
  slot INTEGER,
  slot_count INTEGER,
  type INTEGER,
  status VARCHAR(50),
  booking_type VARCHAR(255),
  dt_created TIMESTAMP,
  dt_updated TIMESTAMP,
  dt_timestamp TIMESTAMP WITHOUT TIME ZONE,
  CONSTRAINT dim_visit_pkey PRIMARY KEY(sk_visit)
) ;