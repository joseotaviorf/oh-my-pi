WITH brokerage_fees AS (
  SELECT
    id_contract_ebdb as sk_contract,
    CAST(accrual_year_month AS INT) as accrual_year_month,
    SUM(invoice_theorical_amount) as revenue_amount
  FROM
    datalake_revenue_lines.brokerage_fee
  WHERE
    brokerage_share = 'quintoandar'
    AND contract_guarantee IN (
      'SeguroFairfax',
      'PRO_GUARANTOR',
      'RentalDeposit',
      'Standalone'
      )
  GROUP BY 1,2
),

management_fees AS (
  SELECT
    id_contract_ebdb as sk_contract,
    CAST(accrual_year_month AS INT) as accrual_year_month,
    SUM(invoice_theorical_amount) AS revenue_amount
  FROM
    datalake_revenue_lines.management_fee
  WHERE
    management_fee_share = 'quintoandar'
  GROUP BY 1,2
),

late_payments AS (
  SELECT
    id_contract as sk_contract,
    CAST(DATE_FORMAT(dt_paid, 'yyyyMM') AS INT) AS accrual_year_month,
    SUM(invoice_paid_amount) AS revenue_amount
  FROM
    datalake_revenue_lines.late_payments
  GROUP BY 1, 2
),

long_term_rental_anticipation AS (
  SELECT
    id_contract_ebdb as sk_contract,
    CAST(DATE_FORMAT(dt_due, 'yyyyMM') AS INT) AS accrual_year_month,
    SUM(mova_interest_value/total_installments) AS revenue_amount
  FROM
    datalake_revenue_lines.long_term_rental_anticipation
  GROUP BY 1,2
),

service_fee AS (
  SELECT
    id_contract_ebdb as sk_contract,
    CAST(accrual_year_month AS INT) as accrual_year_month,
    SUM(invoice_theorical_amount) AS revenue_amount
  FROM
    datalake_revenue_lines.service_fee
  GROUP BY 1,2
),

month_rental_anticipation AS (
  SELECT
    id_contract_ebdb as sk_contract,
    CAST(accrual_year_month AS INT) as accrual_year_month,
    SUM(invoice_paid_fee) AS revenue_amount
  FROM
    datalake_revenue_lines.month_rental_anticipation
  GROUP BY 1,2
),

brokerage_finance AS (
  SELECT
    id_contract_ebdb as sk_contract,
    CAST(accrual_year_month AS INT) as accrual_year_month,
    SUM(invoice_theorical_fee) AS revenue_amount
  FROM
    datalake_revenue_lines.brokerage_finance
  GROUP BY 1,2
),

credit_card_payment AS (
  SELECT
    id_contract_ebdb as sk_contract,
    CAST(DATE_FORMAT(dt_paid, 'yyyyMM') AS INT) AS accrual_year_month,
    SUM(invoice_paid_fee) AS revenue_amount
  FROM
    datalake_revenue_lines.credit_card_payment
  GROUP BY 1,2
),

reservation AS (
  WITH clean_reservation AS (
      SELECT
        r.id_reservation,
        MAX(rf.sk_contract) AS sk_contract,
        CAST(r.accrual_month AS INT) AS accrual_year_month,
        r.monthly_value
      FROM
        datalake_revenue_lines.reservation AS r
      INNER JOIN
        dw_rent.fact_listing_rent_flows AS rf
          ON r.id_reservation = rf.sk_reservation
      WHERE
        rf.sk_contract > 0
        AND r.id_reservation > 0
        AND r.is_ongoing IS NULL
        AND (r.status IN ('FINISHED', 'CHARGED') OR (r.status = 'CANCELED' AND (r.cancellation_reason = 'TENANT_GAVE_UP' OR r.cancellation_reason LIKE '%WITHOUT_CHARGE_BACK')))
      GROUP BY 1,3,4
  )
  SELECT
    sk_contract,
    accrual_year_month,
    sum(monthly_value) as revenue_amount
  FROM
    clean_reservation
  GROUP BY 1,2
),

rental_guarantee AS (
  SELECT
    id_contract as sk_contract,
    CAST(accrual_year_month AS INT) AS accrual_year_month,
    SUM(revenue_qa) AS revenue_amount
  FROM
    datalake_revenue_lines.rental_guarantee
  GROUP BY 1,2
),

fire_insurance AS (
  SELECT
    id_contract,
    CAST(accrual_year_month AS INT) as accrual_year_month,
    SUM(revenue_comission) AS revenue_amount
  FROM
    datalake_revenue_lines.fire_insurance
  GROUP BY 1,2
),

unionall AS (
  SELECT
    *,
    'brokerage_fees' AS revenue_source
  FROM
    brokerage_fees
  UNION ALL
  SELECT
    *,
    'management_fees' AS revenue_source
  FROM
    management_fees
  UNION ALL
  SELECT
    *,
    'late_payments' AS revenue_source
  FROM
    late_payments
  UNION ALL
  SELECT
    *,
    'long_term_rental_anticipation' AS revenue_source
  FROM
    long_term_rental_anticipation
  UNION ALL
  SELECT
    *,
    'rental_guarantee' AS revenue_source
  FROM
    rental_guarantee
  UNION ALL
  SELECT
    *,
    'service_fee' AS revenue_source
  FROM
    service_fee
  UNION ALL
  SELECT
    *,
    'month_rental_anticipation' AS revenue_source
  FROM
    month_rental_anticipation
  UNION ALL
  SELECT
    *,
    'brokerage_finance' AS revenue_source
  FROM
    brokerage_finance
  UNION ALL
  SELECT
    *,
    'credit_card_payment' AS revenue_source
  FROM
    credit_card_payment
  UNION ALL
  SELECT
    *,
    'reservation' AS revenue_source
  FROM
    reservation
  UNION ALL
  SELECT
    *,
    'fire_insurance' AS revenue_source
  FROM
    fire_insurance
)

SELECT
    MONOTONICALLY_INCREASING_ID() AS sk_revenue_lines,
    m.sk_contract,
    accrual_year_month,
    revenue_amount,
    revenue_source,
    TO_DATE(DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(CAST(accrual_year_month AS STRING), 'yyyyMM')), 'yyyy-MM-dd')) AS dt_month_ref,
    NOW() AS ts_load
FROM
    unionall AS m
LEFT JOIN
    (
        SELECT
            distinct *
        FROM
            dw_rent.dim_contract) AS dpdc
    ON dpdc.sk_contract = m.sk_contract
WHERE
    dpdc.country_code = 'BR'
