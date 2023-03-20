SELECT
    id AS id_reviewer,
    user_id AS id_user,
    uuid,
    reviewer_type,
    assessment_id AS id_assessment,
    approved AS is_approved,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.reviewer
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}