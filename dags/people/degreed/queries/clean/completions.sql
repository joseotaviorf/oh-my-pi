SELECT
    id,
    attributes.employee_id AS id_employee_internal,
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
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY
            TO_TIMESTAMP(attributes.added_at) DESC NULLS LAST,
            TO_DATE(attributes.completed_at) DESC NULLS LAST,
            CAST(attributes.points_earned AS FLOAT) DESC NULLS LAST,
            CAST(attributes.rating AS INT) DESC NULLS LAST
    ) = 1
