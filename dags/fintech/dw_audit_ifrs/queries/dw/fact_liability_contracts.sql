WITH dt_start_contract AS (
  SELECT DISTINCT
    CAST(DATE_TRUNC('MONTH', ts_snapshot) AS DATE) - INTERVAL 1 DAY AS dt_closing,
    sk_contract,
    dt_start
  FROM dw_public_snapshot.dim_contract_snapshot
),

assets_info AS (
  SELECT
    c.dt_closing,
    c.sk_contract,
    d.user AS invoice_account_type,
    FALSE AS is_early_bird,
    c.is_guarantee_paid,
    CASE
      WHEN c.is_guarantee_paid IS TRUE THEN 'b. Paid'
      ELSE 'a. Free'
    END AS provisional_group,
    c.closing_month_status,
    d.delay_contamined_range,
    d.delay_contaminated_range_rule_e,
    c.is_write_off,
    lgd.exposure_at_default,
    CASE WHEN c.is_contract_write_off IS TRUE THEN CAST(1 AS DOUBLE) ELSE CAST(lgd.loss_given_default AS DOUBLE) END AS loss_given_default,
    CAST(SUM(-1 * c.due_amount) AS DECIMAL(32, 2)) AS due_amount
  FROM dw_losses.fact_closing AS c
  LEFT JOIN dw_losses.fact_provision AS m
    ON c.sk_invoice = m.sk_invoice AND c.dt_closing = m.dt_closing
  LEFT JOIN dw_losses.fact_delay AS d
    ON d.sk_invoice = m.sk_invoice AND d.dt_closing = m.dt_closing
  LEFT JOIN dt_start_contract AS dsc
    ON c.sk_contract = dsc.sk_contract AND c.dt_closing = dsc.dt_closing
  LEFT JOIN datalake_gsheets_clean.ead_lgd_liability AS lgd
    ON c.dt_closing >= lgd.initial_dt_month_reference
    AND c.dt_closing <= lgd.last_dt_month_reference
    AND dsc.dt_start >= lgd.initial_dt_start_reference
    AND dsc.dt_start <= lgd.last_dt_start_reference
    AND c.is_guarantee_paid = lgd.is_guarantee_paid
    AND -1 * d.delay_contaminated_range_rule_e >= lgd.delay_range_start
    AND -1 * d.delay_contaminated_range_rule_e <= lgd.delay_range_end
  WHERE c.due_amount < 0
    AND (
      (DATE_TRUNC('MONTH', c.dt_closing) <> DATE('2023-01-01') AND c.is_paid_in_closing_day = FALSE)
      OR (
        DATE_TRUNC('MONTH', c.dt_closing) = DATE('2023-01-01')
        AND (c.is_paid_in_closing_day IS TRUE OR c.is_paid_in_closing_day = FALSE)
      )
    )
    AND (
      (DATE_TRUNC('MONTH', c.dt_closing) < DATE('2024-02-01')
        AND (c.has_repair_offboarding_bill_item IS TRUE OR c.has_repair_offboarding_bill_item IS FALSE))
      OR (DATE_TRUNC('MONTH', c.dt_closing) >= DATE('2024-02-01') AND c.has_repair_offboarding_bill_item = FALSE)
    )
    AND c.payment_status <> 'canceled'
    AND COALESCE(c.is_writtendown_in_dead_time, FALSE) = FALSE
    AND (c.is_international = FALSE OR c.is_international IS NULL)
    AND (c.is_before_started = FALSE OR c.is_before_started IS NULL)
    AND (m.invoice_status <> 'Baixado' OR m.invoice_status IS NULL)
    AND c.dt_closing >= DATE('2024-12-31')
  GROUP BY ALL
),

dim_contract AS (
  SELECT
    CAST(DATE_TRUNC('MONTH', a.ts_snapshot) AS DATE) - INTERVAL 1 DAY AS dt_closing,
    a.dt_start,
    a.dt_annulment,
    CAST(a.sk_contract AS DOUBLE) AS sk_contract,
    a.status AS closing_month_status,
    CASE WHEN a.status = 'Ativo' THEN TRUE ELSE FALSE END AS is_ongoing_contract,
    a.first_rent_charged,
    a.rent,
    CASE WHEN b.invoice_account_type IS NULL THEN 'tenant' ELSE b.invoice_account_type END AS invoice_account_type,
    CASE WHEN a.status = 'Ativo' AND b.sk_contract IS NULL THEN TRUE ELSE FALSE END AS is_early_bird,
    CASE
      WHEN (
        UPPER(a.guarantee) = 'RENTALDEPOSIT'
        OR UPPER(a.guarantee) = 'RENTALGUARANTEE'
        OR UPPER(a.guarantee) = 'DEPOSITO'
        OR UPPER(a.guarantee) = 'PRO_GUARANTOR'
        OR UPPER(a.guarantee) = 'THIRDPARTYGUARANTEE'
        OR UPPER(a.guarantee) = 'STANDALONE'
      )
      THEN TRUE
      ELSE FALSE
    END AS is_guarantee_paid,
    CASE
      WHEN (
        UPPER(a.guarantee) = 'RENTALDEPOSIT'
        OR UPPER(a.guarantee) = 'RENTALGUARANTEE'
        OR UPPER(a.guarantee) = 'DEPOSITO'
        OR UPPER(a.guarantee) = 'PRO_GUARANTOR'
        OR UPPER(a.guarantee) = 'THIRDPARTYGUARANTEE'
        OR UPPER(a.guarantee) = 'STANDALONE'
      )
      THEN 'Paid'
      ELSE 'Free'
    END AS guarantee_group,
    b.delay_contaminated_range_rule_e,
    CASE
      WHEN b.delay_contamined_range IS NULL AND a.status = 'Ativo' THEN 'is_early_bird'
      ELSE b.delay_contamined_range
    END AS delay_contamined_range,
    b.exposure_at_default,
    b.loss_given_default,
    CAST(SUM(COALESCE(b.due_amount, 0)) FILTER (WHERE COALESCE(b.is_write_off, FALSE) = FALSE) AS DECIMAL(32, 2)) AS due_amount
  FROM dw_public_snapshot.dim_contract_snapshot AS a
  LEFT JOIN assets_info AS b
    ON a.sk_contract = b.sk_contract
    AND CAST(DATE_TRUNC('MONTH', a.ts_snapshot) AS DATE) - INTERVAL 1 DAY = b.dt_closing
  WHERE DATE(a.ts_snapshot) >= DATE('2025-01-02')
    AND a.country_code = 'BR'
    AND a.status IN ('Ativo', 'Finalizado')
  GROUP BY ALL
),

dim_contract_ecl AS (
  SELECT
    b1.dt_closing,
    b1.dt_start,
    b1.dt_annulment,
    b1.sk_contract,
    b1.closing_month_status,
    b1.first_rent_charged,
    b1.rent,
    b1.invoice_account_type,
    b1.is_early_bird,
    b1.guarantee_group,
    b1.is_ongoing_contract,
    b1.delay_contamined_range,
    CAST(COALESCE(b1.due_amount, 0) AS DECIMAL(32, 2)) AS due_amount,
    CAST(lgd.exposure_at_default AS DOUBLE) AS exposure_at_default,
    CAST(lgd.loss_given_default AS DOUBLE) AS loss_given_default
  FROM dim_contract AS b1
  LEFT JOIN datalake_gsheets_clean.ead_lgd_liability AS lgd
    ON b1.dt_closing >= lgd.initial_dt_month_reference
    AND b1.dt_closing <= lgd.last_dt_month_reference
    AND b1.dt_start >= lgd.initial_dt_start_reference
    AND b1.dt_start <= lgd.last_dt_start_reference
    AND b1.is_guarantee_paid = lgd.is_guarantee_paid
    AND -1 * COALESCE(b1.delay_contaminated_range_rule_e, 10) >= lgd.delay_range_start
    AND -1 * COALESCE(b1.delay_contaminated_range_rule_e, 1) <= lgd.delay_range_end
),

active_liability_contracts AS (
  SELECT
    CAST(sk_contract AS DOUBLE) AS sk_contract,
    dt_closing,
    dt_start,
    dt_annulment,
    closing_month_status,
    first_rent_charged,
    rent,
    invoice_account_type,
    is_early_bird,
    guarantee_group,
    is_ongoing_contract,
    delay_contamined_range,
    CASE
      WHEN delay_contamined_range IN ('a. Current', 'b. 1-30', 'is_early_bird') THEN 'Stage 1'
      WHEN delay_contamined_range IN ('c. 31-60', 'd. 61-90') THEN 'Stage 2'
      WHEN delay_contamined_range IN ('e. 91-120', 'f. 121-150', 'g. 151-180', 'h. acima de 180') THEN 'Stage 3'
      ELSE 'Other'
    END AS initial_delay_stage,
    exposure_at_default,
    loss_given_default,
    CAST(COALESCE(due_amount, 0) AS DECIMAL(32, 2)) AS due_amount,
    NOW() AS ts_load
  FROM dim_contract_ecl
)

SELECT
  sk_contract,
  dt_closing,
  dt_start,
  dt_annulment,
  closing_month_status,
  first_rent_charged,
  rent,
  invoice_account_type,
  is_early_bird,
  guarantee_group,
  is_ongoing_contract,
  delay_contamined_range,
  initial_delay_stage,
  exposure_at_default,
  loss_given_default,
  due_amount,
  ts_load
FROM active_liability_contracts
