WITH
debtors_all_time AS (
  SELECT *,
    CAST(MONTHS_BETWEEN(
      DATE_ADD(
        LAST_DAY(
          ADD_MONTHS(CURRENT_DATE(), -1)), 1
      ),
      DATE_ADD(
        LAST_DAY(
          ADD_MONTHS(dt_contract_signature,-1)), 1
      )
    ) AS INTEGER) AS months_of_contract
  FROM dw_credit_evers.fact_credit_overdue_invoices
  WHERE
    is_debt_forgiveness IS FALSE
    AND dt_contract_signature >= DATE('2018-01-01')
    AND purpose IN ('monthly', 'onboarding')
    AND (paid_amount IS NULL
      OR status <> 'divergent-payment'
        OR (status LIKE 'divergent-payment'
          AND (paid_amount IS NOT NULL
            AND (due_amount + paid_amount)/due_amount < 0.01)))
),
mob_array AS (
  SELECT
    EXPLODE(
      ARRAY(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 30, 40)
    ) AS mob
),
ever_array AS (
  SELECT
    EXPLODE(
      ARRAY(15, 30, 40, 60, 90, 120)
    ) AS ever
),
cross_mob_ever AS (
    SELECT
        d.*,
        ma.mob,
        ea.ever,
        (12*(DATE_FORMAT(DATE_ADD(d.dt_due_adjusted_based_accrual_year_month, ea.ever), "y") -
                  DATE_FORMAT(d.dt_contract_signature, "y")) +
            (DATE_FORMAT(DATE_ADD(d.dt_due_adjusted_based_accrual_year_month, ea.ever), "M") -
                  DATE_FORMAT(d.dt_contract_signature, "M"))) AS invoice_mob,
        CASE
          WHEN d.has_agreement_broken IS TRUE
            AND DATE_DIFF(DATE_TRUNC("MONTH", dt_agreement_cancelation), DATE_TRUNC("MONTH", ADD_MONTHS(d.dt_contract_signature, INT(ma.mob)))) <= 0
            THEN DATE_DIFF(MONTH, DATE_TRUNC("MONTH", d.dt_contract_signature), DATE_TRUNC("MONTH", d.dt_agreement_cancelation))
          ELSE
              (12*(DATE_FORMAT(DATE_ADD(d.dt_due_adjusted_based_accrual_year_month, ea.ever), "y") - DATE_FORMAT(d.dt_contract_signature, "y")) +
                    (DATE_FORMAT(DATE_ADD(d.dt_due_adjusted_based_accrual_year_month, ea.ever), "M") - DATE_FORMAT(d.dt_contract_signature, "M")))
        END AS invoice_mob_with_agreement,
        ADD_MONTHS(d.dt_contract_signature, INT(ma.mob)) AS dt_reference
    FROM
        debtors_all_time AS d
    CROSS JOIN
        mob_array AS ma
    CROSS JOIN
        ever_array AS ea
),
calculate_delay_days AS (
    SELECT
        *,
        DATEDIFF(COALESCE(ts_paid, CURRENT_DATE), dt_due_adjusted_based_accrual_year_month) AS days_due,
        DATEDIFF(COALESCE(IF(has_agreement_broken
            AND DATE_DIFF(DATE_TRUNC("MONTH", dt_agreement_cancelation), DATE_TRUNC("MONTH", dt_reference)) <= 0, NULL, ts_paid), CURRENT_DATE), dt_due_adjusted_based_accrual_year_month) AS days_due_with_agreement
    FROM
        cross_mob_ever
),
calculate_invoice_over AS (
    SELECT
        *,
        CASE
            WHEN days_due >= 120 THEN 120
            WHEN days_due>= 90 THEN 90
            WHEN days_due >= 60 THEN 60
            WHEN days_due >= 40 THEN 40
            WHEN days_due >= 30 THEN 30
            WHEN days_due >= 15 THEN 15
        END AS invoice_over_number,
        CASE
            WHEN days_due_with_agreement >= 120 THEN 120
            WHEN days_due_with_agreement >= 90 THEN 90
            WHEN days_due_with_agreement >= 60 THEN 60
            WHEN days_due_with_agreement >= 40 THEN 40
            WHEN days_due_with_agreement >= 30 THEN 30
            WHEN days_due_with_agreement >= 15 THEN 15
        END AS invoice_over_number_with_agreement
    FROM
        calculate_delay_days AS d
),
ever_rule AS (
    SELECT
        sk_invoice,
        sk_contract,
        sk_contract_retsuko,
        sk_contract_ebdb,
        sk_proposal,
        months_of_contract,
        mob,
        ever,
        days_due,
        days_due_with_agreement,
        invoice_over_number,
        invoice_over_number_with_agreement,
        invoice_mob,
        invoice_mob_with_agreement,
        CASE
            WHEN invoice_over_number >= ever
                AND invoice_mob <= mob
            THEN 1
            ELSE 0
        END AS flag_ever,
        CASE
            WHEN invoice_over_number_with_agreement >= ever
                AND invoice_mob_with_agreement <= mob
            THEN 1
            ELSE 0
        END AS flag_ever_with_agreement,
        due_amount,
        dt_due_calculated,
        dt_contract_signature,
        dt_reference,
        dt_contract_updated
    FROM
        calculate_invoice_over
)
SELECT
    sk_contract,
    sk_contract_retsuko,
    sk_contract_ebdb,
    sk_proposal,
    mob,
    ever,
    CAST(MAX(flag_ever) AS BOOLEAN) AS is_ever,
    CAST(MAX(flag_ever_with_agreement) AS BOOLEAN) AS is_ever_with_agreement,
    dt_contract_signature,
    dt_reference,
    dt_contract_updated
FROM ever_rule
GROUP BY ALL
