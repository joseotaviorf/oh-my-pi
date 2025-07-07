SELECT
    id,
    relationships[0].user.data.id AS id_user,
    relationships[1].skill.data.id AS id_skill,
    relationships[3].rater.data.id AS id_rater,
    attributes.employee_id AS id_employee,
    attributes.skill_name AS skill_name,
    attributes.rating_type AS rating_type,
    attributes.rating_label AS rating_label,
    attributes.certifiable_skill_guid AS guid_certifiable_skill,
    CAST(attributes.rating AS INT) AS rating,
    CAST(attributes.is_endorsed AS BOOLEAN) AS is_endorsed,
    CAST(attributes.is_skill_endorsed AS BOOLEAN) AS is_skill_endorsed,
    TO_TIMESTAMP(attributes.rated_at) AS ts_rated,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.skill_ratings