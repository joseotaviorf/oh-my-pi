WITH invoices AS (
  SELECT DISTINCT
    ies.id_invoice,
    ies.id_contract,
    ie.entry_type,
    brl_entry_due_amount,
    invoice.accrual_year_month
  FROM
    datalake_invoice.invoice_entries AS ies
  INNER JOIN
    datalake_retsuko_clean.invoice
      ON ies.id_invoice = invoice.id_external
  LEFT JOIN
    datalake_retsuko.invoice_entry AS ie
      ON ies.id = ie.id
  WHERE
    ie.entry_type IN ('rental', 'home insurance')
    AND ie.from_account_type = 'tenant'
    AND ie.to_account_type = 'contract'
),

invoices_values AS (
  SELECT
    id_contract,
    SUM(IF(entry_type = 'rental', brl_entry_due_amount, 0)) AS rent_value,
    SUM(IF(entry_type = 'home insurance', brl_entry_due_amount, 0)) AS home_insurance,
    accrual_year_month
  FROM 
    invoices
  GROUP BY 1,4
),

brokerage_fees AS (
  SELECT
    id_contract_ebdb,
    SUM(IF(brokerage_share = 'quintoandar', invoice_theorical_amount, 0)) AS brokerage_fee,
    SUM(IF(brokerage_share = 'partner', invoice_theorical_amount, 0)) AS brokerage_partner_share,
    accrual_year_month
  FROM
    datalake_revenue_lines.brokerage_fee
  WHERE
    brokerage_share IN ('quintoandar', 'partner')
  GROUP BY 1,4
),

management_fees AS (
  SELECT
    id_contract_ebdb,
    SUM(IF(management_fee_share = 'quintoandar', invoice_theorical_amount, 0)) AS administration_fee,
    SUM(IF(management_fee_share = 'partner', invoice_theorical_amount, 0)) AS management_partner_share,
    accrual_year_month
  FROM
    datalake_revenue_lines.management_fee
  WHERE
    management_fee_share IN ('quintoandar', 'partner')
  GROUP BY 1,4
),

late_payments AS (
  SELECT
    id_contract,
    SUM(invoice_theorical_amount) AS invoice_theorical_amount,
    accrual_year_month
  FROM
    datalake_revenue_lines.late_payments
  GROUP BY 1,3
),

long_term_rental_anticipation AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_theorical_amount) AS invoice_theorical_amount,
    accrual_year_month
  FROM
    datalake_revenue_lines.long_term_rental_anticipation
  GROUP BY 1,3
),

service_fee AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_theorical_amount) AS invoice_theorical_amount,
    accrual_year_month
  FROM
    datalake_revenue_lines.service_fee
  GROUP BY 1,3
),

month_rental_anticipation AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_theorical_amount) AS invoice_theorical_amount,
    accrual_year_month
  FROM
    datalake_revenue_lines.month_rental_anticipation
  GROUP BY 1,3
),

brokerage_finance AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_theorical_amount) AS invoice_theorical_amount,
    accrual_year_month
  FROM
    datalake_revenue_lines.brokerage_finance
  GROUP BY 1,3
),

credit_card_payment AS (
  SELECT
    id_contract_ebdb,
    accrual_year_month,
    SUM(invoice_paid_amount + invoice_theorical_amount) - SUM(acquirer_cost + advance_cost) AS ccp_net
  FROM
    datalake_revenue_lines.credit_card_payment
  GROUP BY 1,2
),

reservation AS (
  SELECT
    id_house_listing,
    accrual_month,
    SUM(monthly_value) AS reservation
  FROM
    datalake_revenue_lines.reservation
  WHERE
    NOT (status = 'FINISHED' AND cancellation_reason = 'DOCUMENTATION_REJECTED_WITH_CHARGE_BACK')
  GROUP BY 1, 2
)

SELECT
  MONOTONICALLY_INCREASING_ID() AS sk_house_listing_revenue,
  mf.id_contract_ebdb AS id_contract,
  COALESCE(hl.id_house_listing, hl_.id_house_listing) AS id_house_listing,
  c.id_house,
  h.country_code,
  INT(MONTHS_BETWEEN(dd.month_start, dd_contract.month_start)) AS contract_lifetime,
  iv.rent_value,
  COALESCE(mf.administration_fee, 0) AS administration_fee,
  COALESCE(bf.brokerage_fee, 0) AS brokerage_fee,
  COALESCE(iv.home_insurance, 0) AS home_insurance,
  COALESCE(sf.invoice_theorical_amount, 0) AS service_fee,
  COALESCE(mra.invoice_theorical_amount, 0) AS mra,
  COALESCE(lra.invoice_theorical_amount, 0) AS lra,
  COALESCE(bfi.invoice_theorical_amount, 0) as bfi,
  COALESCE(lp.invoice_theorical_amount, 0) AS lp,
  COALESCE(ccp.ccp_net, 0) AS ccp_net,
  COALESCE(r.reservation, 0) AS reservation,
  COALESCE(bf.brokerage_partner_share, 0) AS brokerage_partner_share,
  COALESCE(mf.management_partner_share, 0) AS management_partner_share,
  dd.quarter,
  mf.accrual_year_month,
  dd.month_start AS dt_month_start,
  NOW() AS ts_load
FROM
  management_fees AS mf
LEFT JOIN
  brokerage_fees AS bf
    ON mf.id_contract_ebdb = bf.id_contract_ebdb
    AND mf.accrual_year_month = bf.accrual_year_month
LEFT JOIN
  service_fee AS sf
    ON mf.id_contract_ebdb = sf.id_contract_ebdb
    AND mf.accrual_year_month = sf.accrual_year_month
LEFT JOIN
  month_rental_anticipation AS mra
    ON mf.id_contract_ebdb = mra.id_contract_ebdb
    AND mf.accrual_year_month = mra.accrual_year_month
LEFT JOIN
  long_term_rental_anticipation AS lra
    ON mf.id_contract_ebdb = lra.id_contract_ebdb
    AND mf.accrual_year_month = lra.accrual_year_month
LEFT JOIN
  late_payments AS lp
    ON mf.id_contract_ebdb = lp.id_contract
    AND mf.accrual_year_month = lp.accrual_year_month
LEFT JOIN
  brokerage_finance AS bfi
    ON mf.id_contract_ebdb = bfi.id_contract_ebdb
    AND mf.accrual_year_month = bfi.accrual_year_month
LEFT JOIN
  credit_card_payment AS ccp
    ON mf.id_contract_ebdb = ccp.id_contract_ebdb
    AND mf.accrual_year_month = ccp.accrual_year_month
LEFT JOIN
  invoices_values AS iv
    ON mf.id_contract_ebdb = iv.id_contract
    AND mf.accrual_year_month = iv.accrual_year_month
LEFT JOIN
  datalake_ebdb_listing.house_listing AS hl
    ON mf.id_contract_ebdb = hl.id_contract
LEFT JOIN
  reservation AS r
    ON hl.id_house_listing = r.id_house_listing
    AND mf.accrual_year_month = r.accrual_month
LEFT JOIN
  datalake_ebdb_contract.contract AS c
    ON mf.id_contract_ebdb = c.id
LEFT JOIN
  datalake_ebdb_country.house AS h
    ON c.id_house = h.id_house
LEFT JOIN
  datalake_ebdb_listing.house_listing AS hl_
    ON c.id_house  = hl_.id_house
    AND c.dt_started >= hl_.ts_listing_version_start
    AND c.dt_started < COALESCE(hl_.ts_listing_version_end, CURRENT_TIMESTAMP())
INNER JOIN
  dw_public.dim_date AS dd
    ON TO_DATE(STRING(mf.accrual_year_month), 'yyyyMM') = dd.date
INNER JOIN
  dw_public.dim_date AS dd_contract
    ON c.dt_started = dd_contract.date
WHERE
  h.country_code = 'BR'