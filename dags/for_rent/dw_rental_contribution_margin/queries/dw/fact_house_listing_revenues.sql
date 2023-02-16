WITH invoices AS (
  SELECT DISTINCT
    ies.id_invoice,
    ies.id_contract,
    ie.entry_type,
    brl_entry_due_amount,
    ie.from_account_type,
    ie.to_account_type,
    invoice.accrual_year_month
  FROM
    datalake_invoice.invoice_entries AS ies
  INNER JOIN
    datalake_retsuko_clean.invoice
      ON ies.id_invoice = invoice.id_external
  LEFT JOIN
    datalake_retsuko.invoice_entry AS ie
      ON ies.id = ie.id
),

invoices_values AS (
  SELECT
    id_contract,
    SUM(IF(entry_type = 'rental', brl_entry_due_amount, 0)) AS rent_value,
    SUM(IF(entry_type = 'home insurance', brl_entry_due_amount, 0)) AS home_insurance,
    accrual_year_month
  FROM 
    invoices
  WHERE
    from_account_type = 'tenant'
    AND to_account_type = 'contract'
  GROUP BY 1,4
),

contracts_competences as (
  SELECT DISTINCT
    id_contract,
    accrual_year_month
  FROM
    invoices
),

brokerage_fees AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_theorical_amount) AS brokerage_fee,
    SUM(IF(brokerage_share = 'partner' AND invoice_payment_status = 'paid', invoice_theorical_amount, 0)) AS brokerage_partner_share,
    SUM(IF(brokerage_share = 'rental agents', prod_theorical_amount, 0)) AS agents_commission,
    accrual_year_month
  FROM
    datalake_revenue_lines.brokerage_fee
  GROUP BY 1, 5
),

management_fees AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_theorical_amount) AS administration_fee,
    SUM(IF(management_fee_share = 'partner', invoice_theorical_amount, 0)) AS management_partner_share,
    accrual_year_month
  FROM
    datalake_revenue_lines.management_fee
  GROUP BY 1, 4
),

late_payments AS (
  SELECT
    id_contract,
    DATE_FORMAT(dt_paid, 'yyyyMM') AS paid_accrual_year_month,
    SUM(invoice_paid_amount) AS lp
  FROM
    datalake_revenue_lines.late_payments
  GROUP BY 1, 2
),

long_term_rental_anticipation AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_theorical_amount) AS lra,
    accrual_year_month
  FROM
    datalake_revenue_lines.long_term_rental_anticipation
  GROUP BY 1, 3
),

service_fee AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_theorical_amount) AS service_fee,
    accrual_year_month
  FROM
    datalake_revenue_lines.service_fee
  GROUP BY 1, 3
),

month_rental_anticipation AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_paid_fee) AS mra,
    accrual_year_month
  FROM
    datalake_revenue_lines.month_rental_anticipation
  GROUP BY 1, 3
),

brokerage_finance AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_paid_fee) AS bfi,
    accrual_year_month
  FROM
    datalake_revenue_lines.brokerage_finance
  GROUP BY 1, 3
),

credit_card_payment AS (
  SELECT
    id_contract_ebdb,
    DATE_FORMAT(dt_paid, 'yyyyMM') AS paid_accrual_year_month,
    SUM(invoice_paid_fee) AS ccp_net
  FROM
    datalake_revenue_lines.credit_card_payment
  GROUP BY 1, 2
),

reservation AS (
  SELECT
    id_house_listing,
    id_house,
    DATE_FORMAT(dt_created, 'yyyyMM') AS created_accrual_year_month,
    SUM(monthly_value) AS reservation
  FROM
    datalake_revenue_lines.reservation
  WHERE
    id_reservation > 0
    AND is_ongoing IS NULL
    AND (status IN ('FINISHED', 'CHARGED') OR (status = 'CANCELED' AND (cancellation_reason = 'TENANT_GAVE_UP' OR cancellation_reason LIKE '%WITHOUT_CHARGE_BACK')))
  GROUP BY 1, 2, 3
),

revenue_with_contract AS (
  SELECT
    MONOTONICALLY_INCREASING_ID() AS sk_house_listing_revenue,
    cc.id_contract,
    hl.id_house_listing,
    hl.id_house,
    INT(MONTHS_BETWEEN(dd.month_start, dd_contract.month_start)) AS contract_lifetime,
    iv.rent_value,
    COALESCE(mf.administration_fee, 0) AS administration_fee,
    COALESCE(bf.brokerage_fee, 0) AS brokerage_fee,
    COALESCE(iv.home_insurance, 0) AS home_insurance,
    COALESCE(sf.service_fee, 0) AS service_fee,
    COALESCE(mra.mra, 0) AS mra,
    COALESCE(lra.lra, 0) AS lra,
    COALESCE(bfi.bfi, 0) as bfi,
    COALESCE(lp.lp, 0) AS lp,
    COALESCE(ccp.ccp_net, 0) AS ccp_net,
    COALESCE(-1 * bf.agents_commission, 0) AS agents_commission,
    COALESCE(bf.brokerage_partner_share, 0) AS brokerage_partner_share,
    COALESCE(mf.management_partner_share, 0) AS management_partner_share,
    dd.quarter,
    cc.accrual_year_month,
    dd.month_start AS dt_month_start
  FROM
    contracts_competences AS cc
  LEFT JOIN
    invoices_values AS iv
      ON cc.id_contract = iv.id_contract
      AND cc.accrual_year_month = iv.accrual_year_month
  LEFT JOIN
    management_fees AS mf
      ON cc.id_contract = mf.id_contract_ebdb
      AND cc.accrual_year_month = mf.accrual_year_month
  LEFT JOIN
    brokerage_fees AS bf
      ON cc.id_contract = bf.id_contract_ebdb
      AND cc.accrual_year_month = bf.accrual_year_month
  LEFT JOIN
    service_fee AS sf
      ON cc.id_contract = sf.id_contract_ebdb
      AND cc.accrual_year_month = sf.accrual_year_month
  LEFT JOIN
    month_rental_anticipation AS mra
      ON cc.id_contract = mra.id_contract_ebdb
      AND cc.accrual_year_month = mra.accrual_year_month
  LEFT JOIN
    long_term_rental_anticipation AS lra
      ON cc.id_contract = lra.id_contract_ebdb
      AND cc.accrual_year_month = lra.accrual_year_month
  LEFT JOIN
    late_payments AS lp
      ON cc.id_contract = lp.id_contract
      AND cc.accrual_year_month = lp.paid_accrual_year_month
  LEFT JOIN
    brokerage_finance AS bfi
      ON cc.id_contract = bfi.id_contract_ebdb
      AND cc.accrual_year_month = bfi.accrual_year_month
  LEFT JOIN
    credit_card_payment AS ccp
      ON cc.id_contract = ccp.id_contract_ebdb
      AND cc.accrual_year_month = ccp.paid_accrual_year_month
  LEFT JOIN
    datalake_ebdb_listing.house_listing AS hl
      ON cc.id_contract = hl.id_contract
  LEFT JOIN
    datalake_ebdb_contract.contract AS c
      ON cc.id_contract = c.id
  INNER JOIN
    dw_public.dim_date AS dd
      ON TO_DATE(STRING(cc.accrual_year_month), 'yyyyMM') = dd.date
  INNER JOIN
    dw_public.dim_date AS dd_contract
      ON c.dt_started = dd_contract.date
)
  
SELECT 
  MONOTONICALLY_INCREASING_ID() AS sk_house_listing_revenue,
  COALESCE(revenue.id_contract, hl.id_contract) AS id_contract,
  COALESCE(r.id_house_listing, revenue.id_house_listing) AS id_house_listing,
  COALESCE(r.id_house, revenue.id_house) AS id_house,
  COALESCE(hl.country_code, 'Undefined') AS country_code,
  contract_lifetime,
  COALESCE(rent_value, 0) AS rent_value,
  COALESCE(administration_fee, 0) AS administration_fee,
  COALESCE(brokerage_fee, 0) AS brokerage_fee,
  COALESCE(home_insurance, 0) AS home_insurance,
  COALESCE(service_fee, 0) AS service_fee,
  COALESCE(mra, 0) AS mra,
  COALESCE(lra, 0) AS lra,
  COALESCE(bfi, 0) AS bfi,
  COALESCE(lp, 0) AS lp,
  COALESCE(ccp_net, 0) AS ccp_net,
  COALESCE(reservation, 0) AS reservation,
  COALESCE(agents_commission, 0) AS agents_commission,
  COALESCE(brokerage_partner_share, 0) AS brokerage_partner_share,
  COALESCE(management_partner_share, 0) AS management_partner_share,
  quarter,
  COALESCE(r.created_accrual_year_month, revenue.accrual_year_month) AS accrual_year_month,
  dt_month_start,
  NOW() AS ts_load
FROM
  revenue_with_contract AS revenue
FULL OUTER JOIN
  reservation AS r
    ON revenue.id_house_listing = r.id_house_listing
    AND revenue.accrual_year_month = r.created_accrual_year_month
LEFT JOIN
  datalake_ebdb_listing.house_listing AS hl
    ON COALESCE(r.id_house_listing, revenue.id_house_listing) = hl.id_house_listing
WHERE
  COALESCE(r.created_accrual_year_month, revenue.accrual_year_month) <= DATE_FORMAT(CURRENT_DATE(), 'yyyyMM')