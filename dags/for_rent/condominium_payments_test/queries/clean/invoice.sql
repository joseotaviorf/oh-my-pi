SELECT
    id,
    external_id AS id_external,
    boleto_user_id AS id_invoice_user,
    contract_id AS id_contract,
    value,
    status,
    raw_data,
    due_date AS dt_due,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_condominium_payments_test_raw.boleto
