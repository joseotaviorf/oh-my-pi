SELECT 
    id,
    user_id AS id_user,
    db_id AS id_database,
    uuid,
    label,
    schema,
    sql,
    description,
    changed_by_fk AS id_user_changed,
    created_by_fk AS id_user_created,
    extra_json,
    last_run,
    rows,
    template_parameters,
    created_on AS ts_created,
    changed_on AS ts_changed,
    year,
    month,
    day
FROM datalake_superset_raw.saved_query
WHERE MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"