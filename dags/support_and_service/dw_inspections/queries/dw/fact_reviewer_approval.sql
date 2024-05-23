SELECT DISTINCT
    r.id_reviewer AS sk_reviewer,
    r.id_assessment AS sk_assessment,
    CAST(r.id_inspection AS STRING) AS sk_inspection,
    r.approval_reason,
    r.approval_comment,
    r.approval_type,
    r.is_approved,
    COALESCE(r.ts_approved, r.ts_updated) AS ts_approved,
    NOW() AS ts_load,
    r.year,
    r.month,
    r.day
FROM
    datalake_inspections.reviewer AS r
WHERE
    r.mod_is_approved IS TRUE
    AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')