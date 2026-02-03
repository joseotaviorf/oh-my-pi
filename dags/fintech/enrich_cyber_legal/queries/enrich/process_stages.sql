WITH
expenses AS (
  SELECT
    id_case,
    id_stage,
    SUM(expense_amount) AS expense_amount
  FROM datalake_cyber_legal_homolog_clean.case_expense
  WHERE is_authorized IS TRUE
    AND is_reimbursed IS TRUE
  GROUP BY 1,2
)
SELECT
    cstg.id_case,
    cstg.stage_order,
    cstg.stage_description,
    cstg.stage_status AS status,
    cstg.dt_stage_start AS dt_start,
    cstg.dt_stage_end AS dt_end,
    cstg.required_days_for_stage AS days_required,
    cstg.authorized_expenses_amount AS authorized_amount,
    cstg.case_subtype AS action,
    COALESCE(cexp.expense_amount, 0) AS expense_amount
FROM
  datalake_cyber_legal_homolog_clean.case_stage AS cstg
LEFT JOIN
    expenses AS cexp
        ON cstg.id_case = cexp.id_case
        AND cstg.id_stage = cexp.id_stage
-- WHERE
    -- cstg.stage_status IN ('Current', 'Completed')
