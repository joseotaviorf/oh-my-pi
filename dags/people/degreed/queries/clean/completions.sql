SELECT
    id,
    attributtes.employee_id AS email_employee,
    attributtes,
    included,
    relationships,
    CAST(attributtes.points_earned AS FLOAT) AS points_earned,
    CAST(attributtes.rating AS INT) AS rating,
    CAST(attributtes.is_verified AS BOOLEAN) AS is_verified,
    TO_DATE(attributtes.completed_at) AS dt_completed,
    TO_TIMESTAMP(attributtes.added_at) AS ts_added,
    NOW() AS ts_load
FROM 
    datalake_degreed_raw.completions
WHERE 
    DATE(attributtes.added_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')