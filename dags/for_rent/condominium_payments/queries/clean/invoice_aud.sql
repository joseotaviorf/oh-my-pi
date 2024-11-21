SELECT
    id,
    external_id AS id_external,
    boleto_user_id AS id_invoice_user,
    contract_id AS id_contract,
    value,
    status,
    raw_data,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    due_date AS dt_due,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_condominium_payments_raw.boleto_aud
