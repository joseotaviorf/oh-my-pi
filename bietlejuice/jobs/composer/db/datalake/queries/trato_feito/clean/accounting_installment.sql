SELECT
    id,
    installment_id AS id_installment,
    external_id AS id_external,
    external_accountant,
    account_payload,
    due_amount,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_trato_feito_raw.accounting_installment