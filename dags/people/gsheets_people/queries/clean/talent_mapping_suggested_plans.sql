SELECT
    NULLIF(quadrant_id, '') AS quadrant_id,
    NULLIF(concept, '') AS concept,
    NULLIF(potential, '') AS potential,
    NULLIF(performance, '') AS performance,
    NULLIF(quadrant, '') AS quadrant,
    NULLIF(quadrant_description, '') AS quadrant_description,
    NULLIF(suggested_action_plans, '') AS suggested_action_plans,
    NOW() AS ts_load
FROM
    datalake_gsheets_people_raw.talent_mapping_suggested_plans
WHERE
    quadrant_id IS NOT NULL
    AND quadrant_id <> ''
