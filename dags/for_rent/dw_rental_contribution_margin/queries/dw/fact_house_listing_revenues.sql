WITH invoices AS (
  SELECT DISTINCT
    ies.id_invoice,
    ies.id_contract,
    ie.entry_type,
    brl_entry_due_amount,
    ii.invoice_user,
    ii.payment_status,
    invoice.accrual_year_month
  FROM
    datalake_invoice.invoice_entries AS ies
  INNER JOIN
    datalake_retsuko.invoice
      ON ies.id_invoice = invoice.id_external
  LEFT JOIN
    datalake_retsuko.invoice_entry AS ie
      ON ies.id = ie.id
  LEFT JOIN
    datalake_retsuko.invoice_info AS ii
      ON invoice.id_external = ii.id_invoice
),

invoices_values AS (
  SELECT
    id_contract,
    SUM(IF(entry_type = 'rental', brl_entry_due_amount, 0)) AS rent_value_invoice,
    accrual_year_month
  FROM
    invoices
  WHERE
    invoice_user = 'tenant'
    AND payment_status != 'canceled'
  GROUP BY 1, 3
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
    SUM(invoice_theorical_amount) AS rental_brokerage,
    SUM(IF(brokerage_share = 'partner' AND invoice_payment_status = 'paid', invoice_theorical_amount, 0)) AS partner_share_brokerage,
    SUM(IF(brokerage_share = 'rental agents', prod_theorical_amount, 0)) AS agents_commission,
    SUM(IF(brokerage_share = 'ciq select', invoice_theorical_amount, 0)) AS select_commission,
    accrual_year_month
  FROM
    datalake_revenue_lines.brokerage_fee
  WHERE
    contract_guarantee IN (
      'SeguroFairfax',
      'PRO_GUARANTOR',
      'RentalDeposit',
      'Standalone'
    )
  GROUP BY 1, 6
),

affiliates_commission AS (
  SELECT
    id_contract_ebdb,
    SUM(IF(brokerage_share = 'ciq', invoice_theorical_amount, 0)) AS affiliates_commission,
    accrual_year_month
  FROM
    datalake_revenue_lines.brokerage_fee
  GROUP BY 1, 3
),

management_fees AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_theorical_amount) AS rental_management,
    SUM(IF(management_fee_share = 'partner', invoice_theorical_amount, 0)) AS partner_share_management,
    accrual_year_month
  FROM
    datalake_revenue_lines.management_fee
  GROUP BY 1, 4
),

late_payments AS (
  SELECT
    id_contract,
    DATE_FORMAT(dt_paid, 'yyyyMM') AS paid_accrual_year_month,
    SUM(invoice_paid_amount) AS late_payments
  FROM
    datalake_revenue_lines.late_payments
  GROUP BY 1, 2
),

long_term_rental_anticipation AS (
  SELECT
    id_contract_ebdb,
    SUM(mova_interest_value/total_installments) AS addons_lra,
    DATE_FORMAT(dt_due, 'yyyyMM') AS due_accrual_year_month,
    dt_due
  FROM
    datalake_revenue_lines.long_term_rental_anticipation
  GROUP BY 1, 3, 4
),

service_fee AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_theorical_amount) AS addons_service_fee,
    accrual_year_month
  FROM
    datalake_revenue_lines.service_fee
  GROUP BY 1, 3
),

month_rental_anticipation AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_paid_fee) AS addons_mra,
    accrual_year_month
  FROM
    datalake_revenue_lines.month_rental_anticipation
  GROUP BY 1, 3
),

brokerage_finance AS (
  SELECT
    id_contract_ebdb,
    SUM(invoice_theorical_fee) AS addons_bfi,
    accrual_year_month
  FROM
    datalake_revenue_lines.brokerage_finance
  GROUP BY 1, 3
),

credit_card_payment AS (
  SELECT
    id_contract_ebdb,
    DATE_FORMAT(dt_paid, 'yyyyMM') AS paid_accrual_year_month,
    SUM(invoice_paid_fee) AS addons_ccp
  FROM
    datalake_revenue_lines.credit_card_payment
  GROUP BY 1, 2
),

reservation AS (
  SELECT
    id_house_listing,
    id_house,
    id_reservation,
    DATE_FORMAT(dt_created, 'yyyyMM') AS created_accrual_year_month,
    SUM(monthly_value) AS addons_reserve
  FROM
    datalake_revenue_lines.reservation
  WHERE
    id_reservation > 0
    AND is_ongoing IS NULL
    AND (status IN ('FINISHED', 'CHARGED') OR (status = 'CANCELED' AND (cancellation_reason = 'TENANT_GAVE_UP' OR cancellation_reason LIKE '%WITHOUT_CHARGE_BACK')))
  GROUP BY 1, 2, 3, 4
),

rental_guarantee AS (
  SELECT
    id_contract,
    SUM(revenue_qa) AS addons_guarantee,
    accrual_year_month
  FROM
    datalake_revenue_lines.rental_guarantee
  WHERE
    guarantee_type <> 'STANDALONE'
  GROUP BY 1,3
),

new_business AS (
  SELECT
    id_contract,
    SUM(revenue_qa) AS addons_new_business_revenue,
    accrual_year_month
  FROM
    datalake_revenue_lines.rental_guarantee
  WHERE
    guarantee_type = 'STANDALONE'
  GROUP BY 1,3
),

insurance_commission AS (
  SELECT
    id_contract,
    SUM(revenue_comission) AS insurance_commission,
    accrual_year_month
  FROM
    datalake_revenue_lines.fire_insurance
  GROUP BY 1,3
),

revenue_with_contract AS (
  SELECT
    MONOTONICALLY_INCREASING_ID() AS sk_house_listing_revenue,
    cc.id_contract,
    hl.id_house_listing,
    hl.id_house,
    INT(MONTHS_BETWEEN(dd.month_start, dd_contract.month_start)) AS contract_lifetime,
    iv.rent_value_invoice,
    COALESCE(mf.rental_management, 0) AS rental_management,
    COALESCE(bf.rental_brokerage, 0) AS rental_brokerage,
    COALESCE(ic.insurance_commission, 0) AS insurance_commission,
    COALESCE(sf.addons_service_fee, 0) AS addons_service_fee,
    COALESCE(mra.addons_mra, 0) AS addons_mra,
    COALESCE(bfi.addons_bfi, 0) as addons_bfi,
    COALESCE(lp.late_payments, 0) AS late_payments,
    COALESCE(ccp.addons_ccp, 0) AS addons_ccp,
    COALESCE(rg.addons_guarantee, 0) AS addons_guarantee,
    COALESCE(-1 * (bf.agents_commission + bf.select_commission), 0) AS agents_commission,
    COALESCE(-1 * ac.affiliates_commission, 0) AS affiliates_commission,
    COALESCE(-1 * bf.partner_share_brokerage, 0) AS partner_share_brokerage,
    COALESCE(-1 * mf.partner_share_management, 0) AS partner_share_management,
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
    affiliates_commission AS ac
      ON cc.id_contract = ac.id_contract_ebdb
      AND cc.accrual_year_month = ac.accrual_year_month
  LEFT JOIN
    service_fee AS sf
      ON cc.id_contract = sf.id_contract_ebdb
      AND cc.accrual_year_month = sf.accrual_year_month
  LEFT JOIN
    month_rental_anticipation AS mra
      ON cc.id_contract = mra.id_contract_ebdb
      AND cc.accrual_year_month = mra.accrual_year_month
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
    rental_guarantee AS rg
      ON cc.id_contract = rg.id_contract
      AND cc.accrual_year_month = rg.accrual_year_month
  LEFT JOIN
    insurance_commission AS ic
      ON cc.id_contract = ic.id_contract
      AND cc.accrual_year_month = ic.accrual_year_month
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
),

revenues_calculation AS (
  SELECT
    MONOTONICALLY_INCREASING_ID() AS sk_house_listing_revenue,
    COALESCE(revenue.id_contract, rf.sk_contract, ltra.id_contract_ebdb, nb.id_contract, -1) AS id_contract,
    COALESCE(r.id_house_listing, revenue.id_house_listing, lc.id_house_listing) AS id_house_listing,
    COALESCE(r.id_house, revenue.id_house, lc.id_house, c.id_house) AS id_house,
    COALESCE(ch.country_code, 'Undefined') AS country_code,
    contract_lifetime,
    COALESCE(rent_value_invoice, 0) AS rent_value_invoice,
    COALESCE(rental_management, 0) AS rental_management,
    COALESCE(rental_brokerage, 0) AS rental_brokerage,
    COALESCE(insurance_commission, 0) AS insurance_commission,
    COALESCE(addons_service_fee, 0) AS addons_service_fee,
    COALESCE(addons_mra, 0) AS addons_mra,
    COALESCE(addons_lra, 0) AS addons_lra,
    COALESCE(addons_bfi, 0) AS addons_bfi,
    COALESCE(late_payments, 0) AS late_payments,
    COALESCE(addons_ccp, 0) AS addons_ccp,
    COALESCE(addons_reserve, 0) AS addons_reserve,
    COALESCE(addons_guarantee, 0) AS addons_guarantee,
    COALESCE(nb.addons_new_business_revenue, 0) AS addons_new_business_revenue,
    COALESCE(agents_commission, 0) AS agents_commission,
    COALESCE(affiliates_commission, 0) AS affiliates_commission,
    COALESCE(partner_share_brokerage, 0) AS partner_share_brokerage,
    COALESCE(partner_share_management, 0) AS partner_share_management,
    COALESCE(dd.quarter, revenue.quarter) AS quarter,
    COALESCE(revenue.accrual_year_month, ltra.due_accrual_year_month, r.created_accrual_year_month, nb.accrual_year_month) AS accrual_year_month,
    COALESCE(dd.month_start, revenue.dt_month_start) AS dt_month_start,
    NOW() AS ts_load
  FROM
    revenue_with_contract AS revenue
  FULL OUTER JOIN
    reservation AS r
      ON revenue.id_house_listing = r.id_house_listing
      AND revenue.accrual_year_month = r.created_accrual_year_month
  LEFT JOIN
    dw_rent.fact_listing_rent_flows AS rf
    ON r.id_reservation = rf.sk_reservation
  FULL OUTER JOIN
    long_term_rental_anticipation AS ltra
      ON revenue.id_contract = ltra.id_contract_ebdb
      AND revenue.accrual_year_month = ltra.due_accrual_year_month
  FULL OUTER JOIN
    new_business AS nb
      ON revenue.id_contract = nb.id_contract
      AND revenue.accrual_year_month = nb.accrual_year_month
  JOIN
    dw_public.dim_date AS dd
      ON TO_DATE(STRING(COALESCE(revenue.accrual_year_month, r.created_accrual_year_month, ltra.due_accrual_year_month, nb.accrual_year_month)), 'yyyyMM') = dd.date
  LEFT JOIN
    datalake_listing_contracts.listing_contracts AS lc
      ON COALESCE(revenue.id_contract, rf.sk_contract, ltra.id_contract_ebdb, nb.id_contract) = lc.id_contract
  LEFT JOIN
    datalake_ebdb_contract.contract AS c
      ON COALESCE(revenue.id_contract, rf.sk_contract, ltra.id_contract_ebdb, nb.id_contract) = c.id
  LEFT JOIN
    datalake_ebdb_country.house AS ch
      ON COALESCE(r.id_house, revenue.id_house, lc.id_house, c.id_house) = ch.id_house
  WHERE
    COALESCE(r.created_accrual_year_month, revenue.accrual_year_month, ltra.due_accrual_year_month, nb.accrual_year_month) <= DATE_FORMAT(CURRENT_TIMESTAMP(), 'yyyyMM')
)

SELECT
  sk_house_listing_revenue,
  id_contract,
  id_house_listing,
  id_house,
  country_code,
  contract_lifetime,
  rent_value_invoice,
  rental_management,
  rental_brokerage,
  insurance_commission,
  late_payments,
  addons_service_fee,
  addons_mra,
  addons_lra,
  addons_bfi,
  addons_ccp,
  addons_guarantee,
  addons_new_business_revenue,
  addons_reserve,
  agents_commission,
  affiliates_commission,
  partner_share_brokerage,
  partner_share_management,
  (rental_management + rental_brokerage + insurance_commission) +
    (addons_service_fee + addons_mra + addons_lra + addons_bfi + late_payments + addons_ccp + addons_reserve + addons_guarantee + addons_new_business_revenue) +
    (agents_commission + affiliates_commission + partner_share_brokerage + partner_share_management) AS net_revenue_pre_taxes,
  (rental_management + rental_brokerage + insurance_commission) +
    (addons_service_fee + addons_mra + addons_lra + addons_bfi + late_payments + addons_ccp + addons_reserve + addons_guarantee + addons_new_business_revenue) AS gross_revenue,
  addons_service_fee + addons_mra + addons_lra + addons_bfi + addons_ccp + addons_reserve + addons_guarantee + addons_new_business_revenue AS addons_revenue_total,
  agents_commission + affiliates_commission + partner_share_brokerage + partner_share_management AS revenue_share_total,
  quarter,
  accrual_year_month,
  dt_month_start,
  ts_load
FROM
  revenues_calculation
