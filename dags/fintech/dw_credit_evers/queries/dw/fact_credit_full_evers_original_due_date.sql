WITH debtors_all_time AS (
  SELECT
    id_invoice,
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    is_debt_forgiveness,
    is_fraud,
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
      WHEN is_over_120 THEN 120
      WHEN is_over_90 THEN 90
      WHEN is_over_60 THEN 60
      WHEN is_over_40 THEN 40
      WHEN is_over_30 THEN 30
      WHEN is_over_15 THEN 15
    END AS invoice_over_number,
    due_amount,
    original_due_date,
    dt_contract_updated,
    ts_signature,
    ts_due
  FROM
    datalake_invoice.credit_invoice_original_due_date_homolog
  WHERE
    ts_signature >= DATE('2018-01-01')
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
    ) AS contract_mob_number
),
ever_array AS (
  SELECT
    EXPLODE(
      ARRAY(15, 30, 40, 60, 90, 120)
    ) AS contract_ever_number
),
ever_rule_debt_forgiveness AS (
  SELECT
      id_invoice,
      id_contract_ebdb,
      id_contract_retsuko,
      id_proposal,
      CAST(months_of_contract AS INTEGER) AS months_of_contract,
      ma.contract_mob_number,
      ea.contract_ever_number,
      CASE
            WHEN invoice_over_number >= ea.contract_ever_number
              AND (12*(DATE_FORMAT(DATE_ADD(original_due_date, ea.contract_ever_number), "y") - DATE_FORMAT(ts_signature, "y")) +
                        (DATE_FORMAT(DATE_ADD(original_due_date, ea.contract_ever_number), "M")-DATE_FORMAT(ts_signature, "M"))) <= ma.contract_mob_number THEN 1
            ELSE 0
          END AS flag_ever,
      invoice_over_number,
      FIRST_VALUE(id_invoice) OVER(PARTITION BY id_contract_ebdb, id_proposal ORDER BY invoice_over_number DESC,original_due_date ASC) AS max_invoice_mob,
      due_amount,
      ts_signature,
      DATE_ADD(ts_signature,INT(contract_mob_number)) AS dt_reference,
      dt_contract_updated
  FROM
      debtors_all_time
  CROSS JOIN
      mob_array AS ma
  CROSS JOIN
      ever_array AS ea
  WHERE 
    is_fraud IS FALSE
),
ever_rule_fraud AS (
  SELECT
      id_invoice,
      id_contract_ebdb,
      id_contract_retsuko,
      id_proposal,
      CAST(months_of_contract AS INTEGER) AS months_of_contract,
      ma.contract_mob_number,
      ea.contract_ever_number,
      CASE
            WHEN invoice_over_number >= ea.contract_ever_number
              AND (12*(DATE_FORMAT(DATE_ADD(original_due_date, ea.contract_ever_number), "y") - DATE_FORMAT(ts_signature, "y")) +
                        (DATE_FORMAT(DATE_ADD(original_due_date, ea.contract_ever_number), "M")-DATE_FORMAT(ts_signature, "M"))) <= ma.contract_mob_number THEN 1
            ELSE 0
          END AS flag_ever,
      invoice_over_number,
      FIRST_VALUE(id_invoice) OVER(PARTITION BY id_contract_ebdb, id_proposal ORDER BY invoice_over_number DESC,original_due_date ASC) AS max_invoice_mob,
      due_amount,
      ts_signature,
      DATE_ADD(ts_signature,INT(contract_mob_number)) AS dt_reference,
      dt_contract_updated
  FROM
      debtors_all_time
  CROSS JOIN
      mob_array AS ma
  CROSS JOIN
      ever_array AS ea
  WHERE 
    is_debt_forgiveness IS FALSE
),
ever_rule AS (
  SELECT
      id_invoice,
      id_contract_ebdb,
      id_contract_retsuko,
      id_proposal,
      CAST(months_of_contract AS INTEGER) AS months_of_contract,
      ma.contract_mob_number,
      ea.contract_ever_number,
      CASE
            WHEN invoice_over_number >= ea.contract_ever_number
              AND (12*(DATE_FORMAT(DATE_ADD(original_due_date, ea.contract_ever_number), "y") - DATE_FORMAT(ts_signature, "y")) +
                        (DATE_FORMAT(DATE_ADD(original_due_date, ea.contract_ever_number), "M")-DATE_FORMAT(ts_signature, "M"))) <= ma.contract_mob_number THEN 1
            ELSE 0
          END AS flag_ever,
      invoice_over_number,
      FIRST_VALUE(id_invoice) OVER(PARTITION BY id_contract_ebdb, id_proposal ORDER BY invoice_over_number DESC,original_due_date ASC) AS max_invoice_mob,
      due_amount,
      ts_signature,
      DATE_ADD(ts_signature,INT(contract_mob_number)) AS dt_reference,
      dt_contract_updated
  FROM
      debtors_all_time
  CROSS JOIN
      mob_array AS ma
  CROSS JOIN
      ever_array AS ea
  WHERE 
        is_debt_forgiveness IS FALSE
    AND is_fraud IS FALSE
),
calculate_final_ever AS (
  SELECT
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    months_of_contract,
    contract_mob_number,
    contract_ever_number,
    MAX(IF(flag_ever = 1, max_invoice_mob, NULL)) AS invoice_anchor,
    CAST(MAX(flag_ever) AS BOOLEAN) AS is_ever,
    CAST(SUM(flag_ever) AS INTEGER) AS num_overs_in_mob_window,
    SUM(IF(flag_ever = 1, due_amount, 0)) AS total_due_amount_in_mob_window,
    CAST(SUM(IF(invoice_over_number >= contract_ever_number,1,0)) AS INTEGER) AS num_total_overs,
    SUM(IF(invoice_over_number >= contract_ever_number,due_amount,0)) AS total_due_amount,
    ts_signature,
    dt_reference,
    dt_contract_updated
FROM ever_rule
GROUP BY
    1,2,3,4,5,6,13,14,15
HAVING
    (is_ever = FALSE
        AND (months_of_contract > contract_mob_number)
            OR (is_ever = TRUE)
            )
),
calculate_final_ever_debt_forgiveness AS (
  SELECT
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    months_of_contract,
    contract_mob_number,
    contract_ever_number,
    MAX(IF(flag_ever = 1, max_invoice_mob, NULL)) AS invoice_anchor,
    CAST(MAX(flag_ever) AS BOOLEAN) AS is_ever,
    CAST(SUM(flag_ever) AS INTEGER) AS num_overs_in_mob_window,
    SUM(IF(flag_ever = 1, due_amount, 0)) AS total_due_amount_in_mob_window,
    CAST(SUM(IF(invoice_over_number >= contract_ever_number,1,0)) AS INTEGER) AS num_total_overs,
    SUM(IF(invoice_over_number >= contract_ever_number,due_amount,0)) AS total_due_amount,
    ts_signature,
    dt_reference,
    dt_contract_updated
FROM ever_rule_debt_forgiveness
GROUP BY
    1,2,3,4,5,6,13,14,15
HAVING
    (is_ever = FALSE
        AND (months_of_contract > contract_mob_number)
            OR (is_ever = TRUE)
            )
),
calculate_final_ever_fraud AS (
  SELECT
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    months_of_contract,
    contract_mob_number,
    contract_ever_number,
    MAX(IF(flag_ever = 1, max_invoice_mob, NULL)) AS invoice_anchor,
    CAST(MAX(flag_ever) AS BOOLEAN) AS is_ever,
    CAST(SUM(flag_ever) AS INTEGER) AS num_overs_in_mob_window,
    SUM(IF(flag_ever = 1, due_amount, 0)) AS total_due_amount_in_mob_window,
    CAST(SUM(IF(invoice_over_number >= contract_ever_number,1,0)) AS INTEGER) AS num_total_overs,
    SUM(IF(invoice_over_number >= contract_ever_number,due_amount,0)) AS total_due_amount,
    ts_signature,
    dt_reference,
    dt_contract_updated
FROM ever_rule_fraud
GROUP BY
    1,2,3,4,5,6,13,14,15
HAVING
    (is_ever = FALSE
        AND (months_of_contract > contract_mob_number)
            OR (is_ever = TRUE)
            )
)
SELECT
    erdf.id_contract_ebdb,
    erdf.id_contract_retsuko,
    erdf.id_proposal,
    erdf.months_of_contract,
    erdf.contract_mob_number,
    erdf.contract_ever_number,
    er.invoice_anchor,
    erdf.invoice_anchor AS invoice_anchor_debt_forgiveness,
    f.invoice_anchor AS invoice_anchor_fraud,
    er.is_ever,
    erdf.is_ever AS is_ever_debt_forgiveness,
    f.is_ever AS is_ever_fraud,
    er.num_overs_in_mob_window,
    erdf.num_overs_in_mob_window AS num_overs_in_mob_window_debt_forgiveness,
    f.num_overs_in_mob_window AS num_overs_in_mob_window_fraud,
    er.num_total_overs,
    erdf.num_total_overs AS num_total_overs_debt_forgiveness,
    f.num_total_overs AS num_total_overs_fraud,
    er.total_due_amount,
    erdf.total_due_amount AS total_due_amount_debt_forgiveness,
    f.total_due_amount AS total_due_amount_fraud,
    erdf.ts_signature,
    erdf.dt_reference,
    erdf.dt_contract_updated
FROM 
  calculate_final_ever_debt_forgiveness AS erdf
LEFT JOIN 
  calculate_final_ever AS er
  ON er.id_contract_retsuko = erdf.id_contract_retsuko
  AND er.contract_mob_number = erdf.contract_mob_number
  AND er.contract_ever_number = erdf.contract_ever_number
LEFT JOIN calculate_final_ever_fraud AS f
  ON f.id_contract_retsuko = erdf.id_contract_retsuko
  AND f.contract_mob_number = erdf.contract_mob_number
  AND f.contract_ever_number = erdf.contract_ever_number

