SELECT
    id                      AS id_feature,
    source_id               AS id_source,
    business_entity_id      AS id_business_entity,
    finance_entity_id       AS id_finance_entity,
    external_payment_id     AS id_external_payment,
    uuid,
    source,
    transaction_type,
    metadata,
    request_payload,
    sync_sap_status,
    source_client,
    user_type,
    finance_entity_type,
    CAST(get_json_object(request_payload, '$.entries[0].amount') AS DECIMAL(10, 2)) AS entry_amount,
    TIMESTAMP(accrual_date) AS ts_accrual,
    created_at              AS ts_created,
    updated_at              AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sap_gateway_raw.feature
