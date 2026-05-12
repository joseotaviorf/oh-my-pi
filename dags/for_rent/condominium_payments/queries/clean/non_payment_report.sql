SELECT
    CAST(id AS BIGINT) AS id,
    CAST(contract_id AS BIGINT) AS id_contract,
    third_party_bill_uuid AS uuid_third_party_bill,
    expense_type,
    created_by,
    notification_source,
    rental_management_sync_initiated AS is_rental_management_sync_initiated,
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_condominium_payments_raw.non_payment_report
