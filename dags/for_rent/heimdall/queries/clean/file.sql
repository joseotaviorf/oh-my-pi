SELECT
    GET_JSON_OBJECT(REPLACE(_id, '$', ''), '$.oid') AS id,
    mimeType AS mime_type,
    type AS type,
    inferenceUuid AS uuid_inference,
    CAST(contractId AS BIGINT) AS id_contract,
    activityId AS id_activity,
    _class AS class,
    externalStorageId AS id_external_storage,
    externalStorageProvider AS external_storage_provider,
    inference,
    CAST(FROM_UNIXTIME(createdAt/1000) AS TIMESTAMP) AS ts_created,
    CAST(FROM_UNIXTIME(updatedAt/1000) AS TIMESTAMP) AS ts_updated
FROM
    datalake_heimdall_raw.file
