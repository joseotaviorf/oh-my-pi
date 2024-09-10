WITH
evicton AS (
  SELECT
    e.id AS id_eviction,
    BIGINT(e.id_external) AS id_contract,
    ed.cpf_client AS id_customer,
    e.law_firm,
    e.status,
    e.ts_status_updated,
    ed.distributor_code_external AS distributor,
    ed.occurrence_code_external AS occurence,
    ed.dt_occurrence_due_date_external AS dt_occurrence_due_date
  FROM datalake_trato_feito_clean.eviction AS e
  LEFT JOIN datalake_trato_feito_clean.eviction_data AS ed
    ON e.id_external = ed.id_external
  WHERE e.status IS NOT NULL
),
contract AS (
  SELECT
    BIGINT(id_contract) AS id_contract,
    id_customer,
    CASE
      WHEN id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
      WHEN id_creditor IN (2,6) THEN "PP QuintoAndar"
    END AS creditor
  FROM datalake_recupera_clean.contracts
  WHERE id_creditor NOT IN (3,5)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_customer, id_contract ORDER BY dt_contract_start DESC) = 1
)
SELECT
  e.id_eviction AS sk_eviction,
  e.id_customer AS sk_debtor,
  e.id_contract,
  c.creditor,
  e.status,
  e.law_firm,
  e.distributor,
  e.occurence,
  e.dt_occurrence_due_date,
  e.ts_status_updated,
  NOW() AS ts_load
FROM evicton AS e
LEFT JOIN contract AS c
  ON e.id_contract = c.id_contract
  AND e.id_customer = c.id_customer
