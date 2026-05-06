SELECT
    CAST(id AS BIGINT) AS id,
    name,
    providerCode AS provider_code,
    userEmail AS user_email,
    sampleData AS sample_data,
    title,
    content,
    language,
    metadata,
    category,
    isManual AS is_manual,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated,
    YEAR(CAST(updatedAt AS TIMESTAMP)) AS year,
    MONTH(CAST(updatedAt AS TIMESTAMP)) AS month,
    DAY(CAST(updatedAt AS TIMESTAMP)) AS day
FROM
    datalake_comms_manager_raw.central_template
