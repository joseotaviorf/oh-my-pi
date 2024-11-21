SELECT
    id,
    boleto_user_id AS id_invoice_user,
    boleto_issuer_id AS id_invoice_issuer,
    contract_id AS id_contract,
    due_date AS dt_due,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_condominium_payments_raw.boleto_user_issuer
