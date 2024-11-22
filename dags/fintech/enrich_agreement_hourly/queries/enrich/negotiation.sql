WITH
deduplicate_payment AS (
  SELECT
    ts_updated,
    type,
    id_installment
  FROM datalake_trato_feito_hourly_clean.payment
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY ts_created DESC) = 1
),
installments AS (
  SELECT
    i.id_negotiation,
    COALESCE(i.external_index + 1, DENSE_RANK() OVER(PARTITION BY i.id_negotiation ORDER BY i.ts_created, i.id_external)) AS installment_number,
    i.status,
    i.total_amount,
    i.dt_due,
    DATE(p.ts_updated) AS dt_paid
  FROM datalake_trato_feito_hourly_clean.installment AS i
  LEFT JOIN deduplicate_payment AS p
    ON p.id_installment = i.id
  WHERE
    MAKE_DATE(i.year, i.month, i.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
  QUALIFY ROW_NUMBER() OVER(PARTITION BY i.id_negotiation, i.external_index ORDER BY i.ts_created DESC) = 1
),
deduplicate_negotiation AS (
  SELECT
    id AS id_negotiation,
    id_collector_external AS id_negotiation_external,
    id_debtor_external AS id_contract,
    consultancy AS agency,
    ts_created AS ts_negotiation_creation,
    year,
    month,
    day
  FROM datalake_trato_feito_hourly_clean.negotiation
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_negotiation ORDER BY ts_created DESC) = 1
),
installment_group_by_negotiation AS (
  SELECT
    n.id_negotiation,
    n.id_negotiation_external,
    n.id_contract,
    n.agency AS id_agency,
    n.ts_negotiation_creation,
    n.year,
    n.month,
    n.day,
    SUM(IF(i.installment_number = 1, i.total_amount, 0)) AS down_payment_amount,
    SUM(IF(i.installment_number = 1 AND i.status = 'paid', i.total_amount, 0)) AS down_payment_paid_amount,
    SUM(i.total_amount) AS total_negotiated_amount,
    MIN(i.dt_due) AS dt_down_payment_due,
    MIN(IF(i.installment_number = 1 AND i.status = 'paid', i.dt_paid, NULL)) AS dt_down_payment
  FROM deduplicate_negotiation AS n
  INNER JOIN installments AS i
    ON i.id_negotiation = n.id_negotiation
  GROUP BY 1,2,3,4,5,6,7,8
)
SELECT
  id_negotiation,
  id_negotiation_external,
  id_contract,
  id_agency,
  down_payment_amount,
  down_payment_paid_amount,
  total_negotiated_amount,
  dt_down_payment_due,
  dt_down_payment,
  ts_negotiation_creation,
  year,
  month,
  day,
  NOW() AS ts_load
FROM installment_group_by_negotiation
