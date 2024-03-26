SELECT DISTINCT
    rr.id_repair_request,
    rr.id_granted_by,
    r.reviewer_type AS exemption_granted_by,
    rr.responsibility,
    rr.is_exempted,
    CASE
        WHEN is_exempted IS TRUE AND r.reviewer_type = "ADMIN" THEN TRUE
        ELSE FALSE
    END AS is_improper_repair,
    rr.ts_granted,
    rr.year,
    rr.month,
    rr.day
FROM
    datalake_inspections_clean.repair_request AS rr
LEFT JOIN
    datalake_inspections_clean.reviewer AS r
        ON r.id_reviewer = rr.id_granted_by
WHERE
    rr.year = {year}
    AND rr.month = {month}
    AND rr.day = {day}