SELECT
    _id AS id,
    hashId AS hash_id,
    attribute,
    fieldName as field_name,
    object,
    owner,
    source,
    pii_investigation_join_field,
    attribute_original_name,
    attribute_name,
    tags,
    comment,
    type,
    CAST(attributeRecordsCount AS INT) AS count_attribute_records,
    CAST(avgRisk AS INT) AS avg_risk,
    CAST(update_date AS TIMESTAMP) AS ts_updated,
    CAST(last_scan_at AS TIMESTAMP) AS ts_last_scan
FROM
    datalake_bigid_raw.scan_results
