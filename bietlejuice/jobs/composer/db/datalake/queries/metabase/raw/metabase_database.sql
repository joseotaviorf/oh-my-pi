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
    auto_run_queries,
    created_at,
    updated_at,
    EXTRACT(year FROM updated_at)::INT AS year,
    EXTRACT(month FROM updated_at)::INT AS month,
    EXTRACT(day FROM updated_at)::INT AS day
FROM
    metabase."metabase_database"
WHERE 
    EXTRACT(year FROM updated_at) = {year}
    AND EXTRACT(month FROM updated_at) = {month}
    AND EXTRACT(day FROM updated_at) = {day}