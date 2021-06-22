SELECT
    id,
    income_id AS id_income,
    from AS income_from,
    amount,
    income_date AS dt_income,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_monopoly_raw.income_reference