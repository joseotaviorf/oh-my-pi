SELECT
    id,
    locale,
    cost_center_code,
    credit,
    debit,
    accrual_year_month,
    created_at AS ts_created
FROM
    datalake_monopoly_raw.accounting_entry