SELECT
    id,
    creator_id AS id_user_creator,
    collection_id AS id_collection,
    name,
    description,
    position,
    collection_position,
    parameters,
    embedding_params,
    archived AS is_archived,
    show_in_getting_started AS has_show_in_getting_started,
    enable_embedding AS is_enabled_for_embedding,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_metabase_raw.report_dashboard
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}