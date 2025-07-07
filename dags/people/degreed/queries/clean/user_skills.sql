SELECT
    id,
    relationships[0].user.data.id AS id_user,
    attributes.skill_id AS id_skill,
    attributes.skill_name AS skill_name,
    attributes.employee_id AS id_employee,
    attributes.certifiable_skill_guid AS id_certifiable_skill,
    attributes.degreed_url AS url_degreed,
    CAST(attributes.target_rating AS DECIMAL(10,2)) AS target_rating,
    CAST(attributes.is_focus AS BOOLEAN) AS is_focus,
    CAST(attributes.is_endorsed AS BOOLEAN) AS is_endorsed,
    TO_TIMESTAMP(attributes.followed_at) AS ts_followed,
    NOW() AS ts_load
FROM 
    datalake_degreed_raw.user_skills