SELECT
    r.id_reviewer AS sk_reviewer,
    r.id_assessment AS sk_assessment,
    CAST(r.id_inspection AS STRING) AS sk_inspection,
    r.approval_reason,
    r.approval_comment,
    r.approval_type,
    r.is_approved,
    r.ts_approved,
    NOW() AS ts_load,
    r.year,
    r.month,
    r.day
FROM
    datalake_inspections.reviewer AS r
WHERE
    r.mod_is_approved IS TRUE
    AND r.year = {year}
    AND r.month = {month}
    AND r.day = {day}