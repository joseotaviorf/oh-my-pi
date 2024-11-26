SELECT
    id,
    email,
    score,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.emailage_result
