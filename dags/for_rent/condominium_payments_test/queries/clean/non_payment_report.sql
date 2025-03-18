SELECT
    CAST(id AS BIGINT) AS id,
    CAST(contract_id AS BIGINT) AS id_contract,
    expense_type,
    created_by,
    notification_source,
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_condominium_payments_test_raw.non_payment_report
