SELECT
    id,
    db_id AS id_database,
    name,
    display_name,
    description,
    rows,
    entity_name,
    entity_type,
    schema,
    fields_hash,
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
    year = {year}
    AND month = {month}
    AND day = {day}