WITH active_asset_contracts AS (
  SELECT DISTINCT
    CAST(c.sk_contract AS DOUBLE) AS sk_contract,
    c.dt_closing,
    CASE WHEN d.user IS NULL THEN 'tenant' ELSE d.user END AS invoice_account_type,
    COALESCE(l.guarantee_group, 'Free') AS guarantee_group,
    l.contract_closing_month_status AS closing_month_status,
    COALESCE(d.delay_contamined_range, l.delay_contaminated_range) AS delay_contamined_range,
    CASE
      WHEN l.delay_contaminated_range IN ('a. Current', 'b. 1-30') THEN 'Stage 1'
      WHEN l.delay_contaminated_range IN ('c. 31-60', 'd. 61-90') THEN 'Stage 2'
      WHEN l.delay_contaminated_range IN (
        'e. 91-120', 'f. 121-150', 'g. 151-180', 'h. acima de 180'
      ) THEN 'Stage 3'
    END AS initial_delay_stage,
    FALSE AS is_early_bird,
    (l.contract_closing_month_status = 'Ativo') AS is_ongoing_contract,
    CASE
      WHEN l.is_contract_write_off IS TRUE THEN CAST(1 AS DOUBLE)
      ELSE CAST(lgd.loss_given_default AS DOUBLE)
    END AS loss_given_default,
    NOW() AS ts_load
  FROM dw_losses.fact_provision AS c
  LEFT JOIN dw_losses.fact_delay AS d
    ON d.sk_invoice = c.sk_invoice AND d.dt_closing = c.dt_closing
  LEFT JOIN dw_losses.fact_losses AS l
    ON c.sk_invoice = l.sk_invoice AND c.dt_closing = l.dt_closing
  LEFT JOIN datalake_gsheets_clean.ead_lgd_asset AS lgd
    ON c.dt_closing >= lgd.initial_dt_month_reference
    AND c.dt_closing <= lgd.last_dt_month_reference
    AND (
      (l.guarantee_group = 'Paid' AND lgd.is_guarantee_paid IS TRUE)
      OR (
        COALESCE(l.guarantee_group, 'Free') = 'Free'
        AND COALESCE(lgd.is_guarantee_paid, FALSE) IS FALSE
      )
    )
    AND -1 * d.delay_contaminated_range_rule_e >= lgd.delay_range_start
    AND -1 * d.delay_contaminated_range_rule_e <= lgd.delay_range_end
  WHERE c.due_amount < 0
    AND c.payment_status <> 'canceled'
    AND COALESCE(c.is_writtendown_in_dead_time, FALSE) = FALSE
    AND (c.is_international = FALSE OR c.is_international IS NULL)
    AND (c.is_before_started = FALSE OR c.is_before_started IS NULL)
)

SELECT
  sk_contract,
  dt_closing,
  invoice_account_type,
  guarantee_group,
  closing_month_status,
  delay_contamined_range,
  initial_delay_stage,
  is_early_bird,
  is_ongoing_contract,
  loss_given_default,
  ts_load
FROM active_asset_contracts
