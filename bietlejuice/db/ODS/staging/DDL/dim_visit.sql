drop table IF EXISTS staging.dim_visit;
create TABLE staging.dim_visit (
  sk_visit INTEGER,
  id_visit INTEGER,
  cd_visit VARCHAR(12),
  day_visit DATE,
  slot INTEGER,
  slot_count INTEGER,
  type INTEGER,
  status VARCHAR(50),
  booking_type VARCHAR(100),
  dt_created TIMESTAMP,
  dt_updated TIMESTAMP,
  dt_timestamp TIMESTAMP WITHOUT TIME ZONE,
  CONSTRAINT dim_visit_pkey PRIMARY KEY(sk_visit)
) ;