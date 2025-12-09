SELECT
    id AS id_importation_error,
    entity,
    type,
    key,
    original_value,
    message,
    metadata,
    relevance_date AS dt_relevance,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(solved_at) AS ts_solved
FROM
    datalake_nazare_raw.importation_error
