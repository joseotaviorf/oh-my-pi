SELECT
    id AS id_reviewer,
    user_id AS id_user,
    assessment_id AS id_assessment,
    uuid,
    reviewer_type,
    approval_reason,
    approval_comment,
    approval_type,
    approved AS is_approved,
    approved_at AS ts_approved,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.reviewer
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
