SELECT 
    id,
    created_by_fk AS id_user_created,
    changed_by_fk AS id_user_changed,
    tab_state_id AS id_tab_state,
    database_id AS id_database,
    extra_json,
    schema,
    "table",
    description,
    expanded,
    created_on AS ts_created,
    changed_on AS ts_changed,
    year,
    month,
    day
FROM datalake_superset_raw.table_schema
WHERE year = {year} AND month = {month} AND day = {day}