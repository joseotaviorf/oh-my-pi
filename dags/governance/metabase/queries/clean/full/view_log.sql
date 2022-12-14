SELECT
    id,
    user_id AS id_user_viewer,
    model_id AS id_model,
    model,
    timestamp AS ts_viewed
FROM
    datalake_metabase_raw.view_log