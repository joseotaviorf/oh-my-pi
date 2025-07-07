SELECT
    id,
    relationships[0].created_by.data.id AS id_user_created_by,
    attributes.employee_id AS id_employee,
    attributes.title,
    attributes.description,
    attributes.experience_type_peer_name,
    attributes.organization_name,
    attributes.seniority,
    attributes.experience_type,
    CAST(attributes.points_earned AS DECIMAL(10, 2)) AS points_earned,
    CAST(attributes.weekly_hours AS INT) AS weekly_hours,
    CAST(attributes.is_current AS BOOLEAN) AS is_current,
    TO_DATE(attributes.start_date) AS dt_start,
    TO_DATE(attributes.end_date) AS dt_end,
    TO_TIMESTAMP(attributes.created_at) AS ts_created,
    TO_TIMESTAMP(attributes.modified_at) AS ts_modified,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.experiences