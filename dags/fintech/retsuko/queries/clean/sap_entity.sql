SELECT
    id,
    sap_gateway_feature_id AS id_sap_gateway_feature,
    finance_entity_id AS id_finance_entity,
    external_id AS id_external,
    status,
    version,
    event,
    failed_status,
    failed_reason,
    failed_payload,
    timestamp(created_at) AS ts_created,
    timestamp(synced_at) AS ts_synced,
    timestamp(skipped_at) AS ts_skipped,
    timestamp(failed_at) AS ts_failed,
    timestamp(updated_at) AS ts_updated
FROM
    datalake_retsuko_raw.sap_entity
