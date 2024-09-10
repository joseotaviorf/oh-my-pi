WITH deduplicate_records AS (
  SELECT
    id_customer,
    customer_name,
    type_boleto_delivery,
    dt_customer_registration
  FROM datalake_recupera_clean.records
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_customer ORDER BY dt_customer_registration DESC) = 1
),
operational_records AS (
  SELECT
    id_distribution,
    id_customer,
    id_operator,
    advisory_code,
    distributor_code,
    distribution_phase,
    collesction_customer_situation
  FROM datalake_recupera_clean.operational_records
  WHERE id_creditor IN (1,2)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_customer ORDER BY ts_last_update DESC) = 1
)
SELECT
  r.id_customer AS sk_debtor,
  r.customer_name,
  opr.id_distribution AS distribution,
  opr.id_operator AS operator,
  NULLIF(opr.advisory_code,'') AS advisory,
  opr.distributor_code AS distributor,
  s.status_description AS status,
  opr.distribution_phase,
  r.type_boleto_delivery,
  r.dt_customer_registration,
  NOW() AS ts_load
FROM deduplicate_records AS r
LEFT JOIN operational_records AS opr
  ON r.id_customer = opr.id_customer
LEFT JOIN datalake_recupera_clean.status AS s
  ON opr.collesction_customer_situation = s.id_status
