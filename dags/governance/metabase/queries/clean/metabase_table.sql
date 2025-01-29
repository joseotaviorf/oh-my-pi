SELECT
    id,
    db_id AS id_database,
    name,
    display_name,
    description,
    entity_name,
    entity_type,
    schema,
    visibility_type,
    active AS is_active,
    show_in_getting_started AS has_table_showing_in_getting_started,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_metabase_raw.metabase_table
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
