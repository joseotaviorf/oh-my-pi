SELECT
    id,
    name,
    document,
    document_type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_condominium_payments_test_raw.boleto_issuer
