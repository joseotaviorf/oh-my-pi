SELECT
    id,
    user_id AS id_user_revisor,
    model_id AS id_model,
    model,
    object,
    message,
    is_reversion,
    is_creation,
    timestamp AS ts_revision
FROM
    datalake_metabase_raw.revision