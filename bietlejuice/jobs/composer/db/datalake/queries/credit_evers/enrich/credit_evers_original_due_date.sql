WITH debtors_all_time AS (
  SELECT
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    MONTHS_BETWEEN(
      DATE_ADD(
        LAST_DAY(
          ADD_MONTHS(CURRENT_DATE(), -1)), 1
      ),
      DATE_ADD(
        LAST_DAY(
          ADD_MONTHS(ts_signature,-1)), 1
      )
    ) AS months_of_contract,
    CASE
      WHEN is_over_180 THEN 180
      WHEN is_over_160 THEN 160
      WHEN is_over_140 THEN 140
      WHEN is_over_120 THEN 120
      WHEN is_over_110 THEN 110
      WHEN is_over_100 THEN 100
      WHEN is_over_90 THEN 90
      WHEN is_over_80 THEN 80
      WHEN is_over_70 THEN 70
      WHEN is_over_60 THEN 60
      WHEN is_over_50 THEN 50
      WHEN is_over_40 THEN 40
      WHEN is_over_30 THEN 30
      WHEN is_over_20 THEN 20
      WHEN is_over_15 THEN 15
      WHEN is_over_10 THEN 10
    END AS invoice_over_number,
    due_amount,
    ts_signature,
    ts_due
  FROM
    datalake_invoice.credit_invoice_original_due_date
  WHERE
    purpose IN ('monthly', 'onboarding')
    AND (paid_amount IS NULL
      OR status <> 'divergent-payment'
        OR (status LIKE 'divergent-payment'
          AND (paid_amount IS NOT NULL
            AND (due_amount + paid_amount)/due_amount < 0.01)))
),
mob_array AS (
  SELECT
    EXPLODE(
      ARRAY(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
    ) AS contract_mob_number
),
ever_array AS (
  SELECT
    EXPLODE(
      ARRAY(10, 15, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 140, 160, 180)
    ) AS contract_ever_number
)
SELECT
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    months_of_contract,
    ma.contract_mob_number,
    ea.contract_ever_number,
    MAX(
      CASE
        WHEN invoice_over_number >= ea.contract_ever_number
          AND (12*(DATE_FORMAT(DATE_ADD(ts_due, ea.contract_ever_number), "y") - DATE_FORMAT(ts_signature, "y")) + 
                     (DATE_FORMAT(DATE_ADD(ts_due, ea.contract_ever_number), "M")-DATE_FORMAT(ts_signature, "M"))) <= ma.contract_mob_number THEN 1
        ELSE 0
      END
    ) AS is_ever,
    SUM(
      CASE
        WHEN invoice_over_number >= ea.contract_ever_number
          AND (12*(DATE_FORMAT(DATE_ADD(ts_due, ea.contract_ever_number), "y") - DATE_FORMAT(ts_signature, "y")) + 
                     (DATE_FORMAT(DATE_ADD(ts_due, ea.contract_ever_number), "M")-DATE_FORMAT(ts_signature, "M"))) <= ma.contract_mob_number THEN 1
        ELSE 0
      END)
    AS num_overs_in_mob_window,
    SUM(
      CASE
        WHEN invoice_over_number >= ea.contract_ever_number
          AND (12*(DATE_FORMAT(DATE_ADD(ts_due, ea.contract_ever_number), "y") - DATE_FORMAT(ts_signature, "y")) + 
                     (DATE_FORMAT(DATE_ADD(ts_due, ea.contract_ever_number), "M")-DATE_FORMAT(ts_signature, "M"))) <= ma.contract_mob_number THEN due_amount
        ELSE 0
      END
    )
    AS total_due_amount_in_mob_window,
    SUM(
      CASE
        WHEN invoice_over_number >= ea.contract_ever_number
          THEN 1
        ELSE 0
      END
    )
    AS num_total_overs,
    SUM(
      CASE
        WHEN invoice_over_number >= ea.contract_ever_number
          THEN due_amount
        ELSE 0
      END
    )
    AS total_due_amount,
    ts_signature
FROM 
    debtors_all_time
CROSS JOIN
    mob_array AS ma
CROSS JOIN
    ever_array AS ea
GROUP BY
    1,2,3,4,5,6,12
HAVING 
    (is_ever = 0 
        AND (months_of_contract > ma.contract_mob_number)
            OR (is_ever = 1))