WITH contestation_media AS (
    SELECT
        orm.id_origin AS id_contestation,
        COUNT(DISTINCT orm.id_media) AS total_media
    FROM
        datalake_inspections.report_review_media AS orm
    WHERE
        orm.origin = "contestation"
        AND orm.year <= {year}
        AND orm.month <= {month}
        AND orm.day <= {day}
    GROUP BY 1
)
SELECT DISTINCT
    c.id_contestation AS sk_contestation,
    c.id_repair_request AS sk_repair_request,
    c.id_reviewer AS sk_reviewer,
    COALESCE(cm.total_media, 0) <> 0 AS has_media,
    r.reviewer_type = "TENANT" AS is_contested_by_tenant,
    r.reviewer_type = "OWNER" AS is_contested_by_owner,
    c.ts_created,
    c.ts_updated,
    NOW() AS ts_load,
    c.year,
    c.month,
    c.day
FROM
    datalake_inspection_services_clean.contestation AS c
LEFT JOIN
    contestation_media AS cm
        ON cm.id_contestation = c.id_contestation
LEFT JOIN
    datalake_inspection_services_clean.reviewer AS r
        ON r.id_reviewer = c.id_reviewer
WHERE
    MAKE_DATE(c.year, c.month, c.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
