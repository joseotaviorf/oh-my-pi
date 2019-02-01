DROP VIEW IF EXISTS vw_dim_reservation;
CREATE OR REPLACE VIEW vw_dim_reservation as
SELECT
  id as sk_reservation,
  id as id,
  created_at as ts_created,
  updated_at as ts_updated,
  version,
  attempt,
  status,
  value,
  is_ongoing
FROM
  public.reservation;