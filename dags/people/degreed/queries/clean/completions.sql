SELECT
    id,
    attributes.employee_id AS email_employee,
    attributes,
    included,
    relationships,
    CAST(attributes.points_earned AS FLOAT) AS points_earned,
    CAST(attributes.rating AS INT) AS rating,
    CAST(attributes.is_verified AS BOOLEAN) AS is_verified,
    TO_DATE(attributes.completed_at) AS dt_completed,
    TO_TIMESTAMP(attributes.added_at) AS ts_added,
    NOW() AS ts_load
FROM 
    datalake_degreed_raw.completions
WHERE 
    DATE(attributes.added_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')