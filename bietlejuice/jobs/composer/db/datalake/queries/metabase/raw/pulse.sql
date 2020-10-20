SELECT
    id,
    creator_id,
    collection_id,
    name,
    collection_position,
    alert_condition,
    archived,
    skip_if_empty,
    alert_first_only,
    alert_above_goal,
    created_at,
    updated_at,
    EXTRACT(year FROM updated_at)::INT AS year,
    EXTRACT(month FROM updated_at)::INT AS month,
    EXTRACT(day FROM updated_at)::INT AS day
FROM
    metabase."pulse"
WHERE 
    EXTRACT(year FROM updated_at) = {year}
    AND EXTRACT(month FROM updated_at) = {month}
    AND EXTRACT(day FROM updated_at) = {day}