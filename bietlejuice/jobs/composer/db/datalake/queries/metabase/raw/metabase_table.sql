SELECT
    id,
    db_id,
    name,
    display_name,
    description,
    entity_name,
    entity_type,
    schema,
    visibility_type,
    active,
    show_in_getting_started,
    created_at,
    updated_at,
    EXTRACT(year FROM updated_at)::INT AS year,
    EXTRACT(month FROM updated_at)::INT AS month,
    EXTRACT(day FROM updated_at)::INT AS day
FROM
    metabase."metabase_table"
WHERE 
    EXTRACT(year FROM updated_at) = {year}
    AND EXTRACT(month FROM updated_at) = {month}
    AND EXTRACT(day FROM updated_at) = {day}