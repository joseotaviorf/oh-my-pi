WITH guarantee_last_updates AS (
  SELECT
    g.*,
    ROW_NUMBER() OVER (PARTITION BY id_documentation_ebdb ORDER BY ts_updated DESC) AS rownum 
  FROM
    datalake_rental_guarantee_clean.guarantee AS g
)

SELECT
  id,
  id_contract_ebdb,
  id_documentation_ebdb,
  id_house_ebdb,
  id_tenant_ebdb,
  cancellation_reason,
  guarantee_source,
  guarantee_status,
  guarantee_type,
  base_value,
  final_value,
  score,
  accepted_terms_and_conditions AS has_accepted_terms_and_conditions,
  ts_created,
  ts_updated,
  ts_billed,
  ts_cancellation_requested,
  ts_expired,
  ts_paid,
  ts_payment_expired,
  ts_started
FROM
  guarantee_last_updates
WHERE
  rownum = 1