SELECT
    id,
    creator_id,
    database_id,
    table_id,
    collection_id,
    name,
    description,
    display,
    query_type,
    dataset_query,
    visualization_settings,
    embedding_params,
    enable_embedding,
    archived,
    created_at,
    updated_at,
    EXTRACT(year FROM updated_at)::INT AS year,
    EXTRACT(month FROM updated_at)::INT AS month,
    EXTRACT(day FROM updated_at)::INT AS day
FROM
    metabase."report_card"
WHERE 
    EXTRACT(year FROM updated_at) = {year}
    AND EXTRACT(month FROM updated_at) = {month}
    AND EXTRACT(day FROM updated_at) = {day}