SELECT
    id,
    table_id,
    parent_id,
    fk_target_field_id,
    name,
    display_name,
    description,
    base_type,
    special_type,
    position,
    has_field_values,
    visibility_type,
    fingerprint,
    fingerprint_version,
    database_type,
    settings,
    active,
    preview_display, 
    last_analyzed,
    created_at,
    updated_at,
    EXTRACT(year FROM updated_at)::INT AS year,
    EXTRACT(month FROM updated_at)::INT AS month,
    EXTRACT(day FROM updated_at)::INT AS day
FROM
    metabase."metabase_field"
WHERE 
    EXTRACT(year FROM updated_at) = {year}
    AND EXTRACT(month FROM updated_at) = {month}
    AND EXTRACT(day FROM updated_at) = {day}