SELECT
    id,
    name,
    description,
    details,
    engine,
    options,
    timezone,
    is_on_demand,
    is_sample,
    is_full_sync,
    auto_run_queries AS has_auto_run_queries,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_metabase_raw.metabase_database
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}