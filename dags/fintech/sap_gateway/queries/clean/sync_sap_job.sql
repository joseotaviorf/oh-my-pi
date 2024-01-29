SELECT
    id                      AS id_sync_sap_job,
    feature_id              AS id_feature,
    `hash`,
    response,
    `type`,
    `status`,
    erp_solution,
    sap_payload,
    charge_back_of,
    error,
    retryable,
    synced_at               AS ts_synced,
    created_at              AS ts_created,
    updated_at              AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sap_gateway_raw.sync_sap_job
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
