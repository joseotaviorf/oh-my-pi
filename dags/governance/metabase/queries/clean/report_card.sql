SELECT
    id,
    creator_id AS id_user_creator,
    database_id AS id_database,
    table_id AS id_table,
    collection_id AS id_collection,
    name,
    description,
    display,
    query_type,
    dataset_query,
    visualization_settings,
    embedding_params,
    enable_embedding AS is_enabled_for_embedding,
    archived AS is_archived,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_metabase_raw.report_card
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
