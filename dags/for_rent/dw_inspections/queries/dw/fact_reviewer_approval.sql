WITH ranked_reviewer AS (
    SELECT
        r.id_reviewer AS sk_reviewer,
        r.id_assessment AS sk_assessment,
        CAST(r.id_inspection AS STRING) AS sk_inspection,
        r.approval_reason,
        r.approval_comment,
        r.approval_type,
        r.is_approved,
        COALESCE(r.ts_approved, r.ts_updated) AS ts_approved,
        r.year,
        r.month,
        r.day,
        ROW_NUMBER() OVER (PARTITION BY r.id_reviewer ORDER BY COALESCE(r.ts_approved, r.ts_updated) DESC) AS rn
    FROM
        datalake_inspections.reviewer AS r
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT DISTINCT
    sk_reviewer,
    sk_assessment,
    sk_inspection,
    approval_reason,
    approval_comment,
    approval_type,
    is_approved,
    ts_approved,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    ranked_reviewer
WHERE
    rn = 1
