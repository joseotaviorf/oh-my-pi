SELECT
    id,
    ELEMENT_AT(included, 1).id AS id_content,
    ELEMENT_AT(
        FILTER(relationships, r -> r IS NOT NULL AND r.user IS NOT NULL), 1
    ).user.data.id AS id_user,
    CASE
        WHEN REGEXP_LIKE(id_employee_internal, '^[0-9]{{6}}$') THEN id_employee_internal
        ELSE NULL
    END AS person_number,
    CASE
        WHEN NOT REGEXP_LIKE(id_employee_internal, '^[0-9]{{6}}$') THEN id_employee_internal
        ELSE NULL
    END AS employee_email,
    attributes.access_method AS access_method,
    points_earned,
    rating,
    is_verified,
    dt_completed,
    ts_added,
    NOW() AS ts_load
FROM
    datalake_degreed_clean.completions
