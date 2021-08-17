SELECT
    id,
    sale_id AS id_sale,
    income_reference_id AS id_income_reference,
    outcome_reference_id AS id_outcome_reference,
    event,
    description,
    status,
    reversed_by,
    accounting_date AS dt_accounting,
    reversed_at AS ts_reversed,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_monopoly_raw.sale_transaction