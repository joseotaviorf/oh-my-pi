WITH
exclusion_list_bill_items AS (
  SELECT DISTINCT
    sk_invoice,
    dt_closing,
    bill_item_name
  FROM dw_losses.dim_bill_items
  WHERE LOWER(bill_item_name) IN ('non protection 5a','early termination fee non protection','repair offboarding')
),
invoice_anchor AS (
  SELECT
    sk_invoice,
    sk_anchor_invoice,
    MAX(IF(sk_negotiation_created_by IS NULL, dt_due_adjusted, NULL)) OVER(PARTITION BY sk_anchor_invoice) AS dt_due_invoice_anchor
  FROM dw_collection_recovery_quintoandar.fact_renegotiations
),
max_closing AS (
  SELECT
    MAX(dt_closing) AS max_dt_closing
  FROM dw_losses.fact_losses
),
base_write_off AS (
  SELECT
    fl.sk_invoice,
    fl.sk_contract,
    bi.bill_item_name AS bill_tem,
    i.status AS invoice_status,
    fl.payment_status AS invoice_status_at_closing,
    fl.invoice_account_type,
    fl.contract_closing_month_status,
    DATEDIFF(MONTH, fl.dt_contract_annulment, fl.dt_closing) AS months_contract_annulment,
    DATE_DIFF(fl.dt_closing, DATE(i.ts_due)) days_overdue,
    fl.deal_status,
    CASE
        WHEN fl.deal_status IN ('DEAL IN DELAY', 'DEAL ON TIME. DELAY AT ANCHOR')
          AND ia.dt_due_invoice_anchor IS NOT NULL
          THEN DATE_DIFF(fl.dt_closing, ia.dt_due_invoice_anchor)
        ELSE DATE_DIFF(fl.dt_closing, DATE(i.ts_due))
    END AS delay_days_wo,
    fl.due_amount,
    fl.dt_closing,
    fl.dt_contract_annulment,
    ia.dt_due_invoice_anchor,
    DATE(i.ts_due) AS dt_due,
    i.dt_due_adjusted,
    fl.dt_due_invoice_adjusted AS dt_due_at_closing,
    DATE(i.ts_created) AS dt_invoice_created,
    fl.dt_invoice_created As dt_invoice_created_at_closing
  FROM
    dw_losses.fact_losses AS fl
  INNER JOIN
    max_closing AS mc
      ON fl.dt_closing = mc.max_dt_closing
  LEFT JOIN
    exclusion_list_bill_items AS bi
      ON fl.sk_invoice = bi.sk_invoice
        AND fl.dt_closing = bi.dt_closing
  LEFT JOIN
    datalake_retsuko.invoice AS i
      ON i.id_external = fl.sk_invoice
  LEFT JOIN
    invoice_anchor AS ia
      ON ia.sk_invoice = fl.sk_invoice
  WHERE
    IFNULL(i.is_write_off, FALSE) IS FALSE
    AND i.ts_write_off IS NULL
),
invoice_write_off AS (
    SELECT
      *,
      CASE
        WHEN invoice_status = "open"
        AND months_contract_annulment >= 3
        AND invoice_account_type = "Inquilino"
        AND bill_tem IS NULL
        AND contract_closing_month_status = 'Finalizado'
        AND ((delay_days_wo >= 190
                AND due_amount  <= 15000)
              OR (delay_days_wo >= 375
                AND due_amount BETWEEN 15000 and 100000))
        AND YEAR(dt_invoice_created) < YEAR(CURRENT_DATE)
        THEN TRUE
        ELSE FALSE
      END AS is_invoice_write_off_eligible
    FROM base_write_off
),
contract_write_off AS (
  SELECT
    *,
    MIN(is_invoice_write_off_eligible) OVER(PARTITION BY sk_contract) AS is_contract_write_off_eligible
  FROM invoice_write_off
)
SELECT
    sk_invoice,
    sk_contract,
    bill_tem,
    invoice_status,
    invoice_status_at_closing,
    invoice_account_type,
    contract_closing_month_status,
    months_contract_annulment,
    deal_status,
    is_invoice_write_off_eligible,
    is_contract_write_off_eligible,
    days_overdue,
    delay_days_wo,
    due_amount,
    dt_closing,
    dt_contract_annulment,
    dt_due_invoice_anchor,
    dt_due,
    dt_due_adjusted,
    dt_due_at_closing,
    dt_invoice_created,
    dt_invoice_created_at_closing
FROM
  contract_write_off
WHERE
  is_invoice_write_off_eligible IS TRUE
  OR is_contract_write_off_eligible IS TRUE
