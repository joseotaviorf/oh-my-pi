WITH
losses_base AS (
    SELECT DISTINCT
      fp.sk_contract,
      fp.sk_invoice,
      fp.invoice_account_type,
      fp.payment_status,
      fp.invoice_status,
      fc.invoice_type,
      fc.closing_month_status AS contract_closing_month_status,
      CASE
            WHEN fp.risk_type = 'LR' THEN 'a.Low_Risk'
            WHEN fp.risk_type = 'HR' THEN 'b.High_Risk'
      END AS risk_group,
      CASE
        WHEN fc.is_guarantee_paid = false THEN 'c.Free'
        WHEN fc.is_guarantee_paid = true THEN 'd.Paid'
      END AS guarantee_group,
        CASE
            WHEN fp.dt_closing BETWEEN DATE('2021-12-31') AND DATE('2022-11-30') AND fp.risk_type = 'LR' THEN 'a.Low_Risk'
            WHEN fp.dt_closing BETWEEN DATE('2021-12-31') AND DATE('2022-11-30') AND fp.risk_type = 'HR' THEN 'b.High_Risk'
            WHEN fp.dt_closing >= DATE('2022-12-31') AND fc.is_guarantee_paid = false THEN 'c.Free'
            WHEN fp.dt_closing >= DATE('2022-12-31') AND fc.is_guarantee_paid = true THEN 'd.Paid'
            ELSE ''
        END AS provisional_group,
      fp.is_before_started,
      fp.is_international,
      fp.is_writtendown_in_dead_time,
      fp.has_repair_offboarding_bill_item,
      fp.is_write_off,
      fp.is_contract_write_off,
      fc.city,
      fp.delay_contamined_range AS delay_contaminated_range,
      fp.provision_factor,
      fp.provision_balance,
      fp.due_amount,
      fp.dt_closing,
      DATE(DATEADD(DAY, -1, DATE_TRUNC('month', fp.dt_closing))) AS dt_closing_previous,
      fp.dt_due_adjs AS dt_due_invoice_adjusted,
      fc.dt_contract_signature,
      fc.dt_annulment AS dt_contract_annulment,
      fp.dt_snapshot,
      fp.dt_write_off
    FROM dw_losses.fact_provision fp
    LEFT JOIN
        dw_losses.fact_closing AS fc
        ON fp.sk_invoice = fc.sk_invoice
        AND fp.sk_contract = fc.sk_contract
        AND fp.dt_closing = fc.dt_closing
    WHERE fp.due_amount < 0
      AND fp.payment_status <> 'canceled'
      AND fp.is_writtendown_in_dead_time = FALSE
      AND fp.is_international = FALSE
      AND fp.is_before_started = FALSE
      AND (
        (DATE_TRUNC('month', fp.dt_closing) < DATE('2024-02-01') AND fp.has_repair_offboarding_bill_item IS NOT NULL)
        OR (DATE_TRUNC('month', fp.dt_closing) >= DATE('2024-02-01') AND fp.has_repair_offboarding_bill_item = FALSE)
      )
)
SELECT
  COALESCE(la.sk_contract, la2.sk_contract) AS sk_contract,
  COALESCE(la.sk_invoice, la2.sk_invoice) AS sk_invoice,
  COALESCE(la.invoice_account_type, la2.invoice_account_type) AS invoice_account_type,
  COALESCE(la.payment_status, 'paid') AS payment_status,
  COALESCE(la.invoice_status, 'Pago') AS invoice_status,
  COALESCE(la.invoice_type, la2.invoice_type) AS invoice_type,
  COALESCE(la.contract_closing_month_status, la2.contract_closing_month_status) AS contract_closing_month_status,
  COALESCE(la.is_before_started, la2.is_before_started) AS is_before_started,
  COALESCE(la.is_international, la2.is_international) AS is_international,
  COALESCE(la.is_writtendown_in_dead_time, la2.is_writtendown_in_dead_time) AS is_writtendown_in_dead_time,
  COALESCE(la.is_write_off, la2.is_write_off) AS is_write_off,
  COALESCE(la.is_contract_write_off, la2.is_contract_write_off) AS is_contract_write_off,
  COALESCE(la.has_repair_offboarding_bill_item, la2.has_repair_offboarding_bill_item) AS has_repair_offboarding_bill_item,
  COALESCE(la.city, la2.city) AS city,
  COALESCE(la.risk_group, la2.risk_group) AS risk_group,
  COALESCE(la.guarantee_group, la2.guarantee_group) AS guarantee_group,
  COALESCE(la.provisional_group, la2.provisional_group) AS provisional_group,
  COALESCE(la.delay_contaminated_range, la2.delay_contaminated_range) AS delay_contaminated_range,
  COALESCE(la.provision_factor, la2.provision_factor) AS provision_factor,
  ABS(COALESCE(la.due_amount, 0)) AS due_amount,
  ABS(COALESCE(la.provision_balance, 0)) AS provision_balance,
  ABS(COALESCE(la2.provision_balance, 0)) AS previous_provision_balance,
  ABS(COALESCE(la.provision_balance, 0)) - ABS(COALESCE(la2.provision_balance, 0)) AS losses,
  COALESCE(la.dt_snapshot, la2.dt_snapshot) AS dt_snapshot,
  COALESCE(la.dt_due_invoice_adjusted, la2.dt_due_invoice_adjusted) AS dt_due_invoice_adjusted,
  COALESCE(la.dt_contract_annulment, la2.dt_contract_annulment) AS dt_contract_annulment,
  COALESCE(la.dt_write_off, la2.dt_write_off) AS dt_write_off,
  COALESCE(la.dt_closing, LAST_DAY(DATEADD(month, 1, la2.dt_closing))) AS dt_closing
FROM losses_base la
FULL OUTER JOIN losses_base la2
  ON la.sk_contract = la2.sk_contract
    AND la.sk_invoice = la2.sk_invoice
    AND la.dt_closing_previous = la2.dt_closing
WHERE COALESCE(la.dt_closing, LAST_DAY(DATEADD(month, 1, la2.dt_closing))) < LAST_DAY(CURRENT_DATE)
