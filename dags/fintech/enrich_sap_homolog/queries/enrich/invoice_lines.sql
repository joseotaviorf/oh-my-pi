WITH cte_most_recent AS (
    SELECT
        id_transaction,
        id_line,
        MAX(MAKE_DATE(year, month, day)) AS dt_last_updated
    FROM
        datalake_pas_clean.invoice_lines
    GROUP BY 1, 2
)

SELECT DISTINCT
    t1.id_transaction,
    t1.id_line,
    t1.id_business_entity,
    t1.id_finance_entity_entry,
    t1.id_finance_entity,
    t1.id_document,
    t1.id_branch,
    t1.cost_center_code,
    t1.contra_act,
    t1.location_profit_code,
    t1.managerial_code,
    t1.memo_line,
    t1.sap_document_number,
    t1.source_document_number,
    t1.series,
    t1.account,
    t1.account_shortname,
    t1.accounting_rule,
    t1.accounting_type,
    t1.user_type,
    t1.transaction_type,
    t1.accrual_year_month,
    t1.credit,
    t1.debit,
    t1.dt_due,
    t1.dt_reference,
    t1.dt_tax,
    t1.year,
    t1.month,
    t1.day
FROM
    datalake_pas_clean.invoice_lines AS t1
RIGHT JOIN
    cte_most_recent AS cte
    ON cte.id_transaction = t1.id_transaction
    AND cte.id_line = t1.id_line
    AND cte.dt_last_updated = MAKE_DATE(t1.year, t1.month, t1.day)
