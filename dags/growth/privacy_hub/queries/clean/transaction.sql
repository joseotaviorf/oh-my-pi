SELECT
    CAST(id AS BIGINT) AS id,
    CAST(data_subject_id AS BIGINT) AS id_data_subject,
    request_id  AS id_request,
    operator_id AS id_operator,
    origin,
    document_alias,
    document_version,
    purpose_alias,
    purpose_status,
    type,
    result,
    custom_attributes,
    CAST(created_at AS TIMESTAMP) AS ts_created_at,
    CAST(updated_at AS TIMESTAMP) AS ts_updated_at,
    YEAR(CAST(updated_at AS TIMESTAMP)) AS year,
    MONTH(CAST(updated_at AS TIMESTAMP)) AS month,
    DAY(CAST(updated_at AS TIMESTAMP)) AS day
FROM datalake_privacy_hub_raw.transaction
