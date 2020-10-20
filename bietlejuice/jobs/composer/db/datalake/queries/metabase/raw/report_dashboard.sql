SELECT
    id,
    creator_id,
    collection_id,
    name,
    description,
    position,
    collection_position,
    parameters,
    embedding_params,
    archived,
    show_in_getting_started,
    enable_embedding,
    created_at,
    updated_at,
    EXTRACT(year FROM updated_at)::INT AS year,
    EXTRACT(month FROM updated_at)::INT AS month,
    EXTRACT(day FROM updated_at)::INT AS day
FROM
    metabase."report_dashboard"
WHERE 
    EXTRACT(year FROM updated_at) = {year}
    AND EXTRACT(month FROM updated_at) = {month}
    AND EXTRACT(day FROM updated_at) = {day}