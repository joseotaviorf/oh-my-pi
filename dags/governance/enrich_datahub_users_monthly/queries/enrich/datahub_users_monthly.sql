-- Grain: calendar month only. Employment and tool usage count if they overlap the month by >= 1 day (any day in the month).
WITH bounds AS (
    SELECT
        TRUNC(CAST('{reference_month_end}' AS DATE), 'MM') AS month_start,
        CAST('{reference_month_end}' AS DATE) AS month_end
),
all_employees AS (
    SELECT
        work_email,
        job_class,
        business,
        product,
        vertical,
        line,
        chapter,
        directorate,
        assignment_status_type,
        dt_hired,
        dt_terminated,
        CASE
            WHEN chapter = 'Data' OR directorate = 'Dados' THEN 'Tech - Data'
            ELSE COALESCE(vertical, 'Corp')
        END AS area_class
    FROM
        datalake_people_public.org_chart
),
eligible_employees AS (
    SELECT
        e.*
    FROM
        all_employees AS e
    CROSS JOIN bounds AS b
    WHERE
        e.dt_hired IS NOT NULL
        AND e.dt_hired <= b.month_end
        AND (
            e.dt_terminated IS NULL
            OR e.dt_terminated >= b.month_start
        )
),
datahub_users_month AS (
    SELECT DISTINCT
        element_at(split(id_user, 'urn:li:corpuser:'), 2) AS user_email
    FROM
        datalake_amplitude_clean.events
    CROSS JOIN bounds AS b
    WHERE
        id_app = '417002'
        AND CAST(ts_event AS DATE) >= b.month_start
        AND CAST(ts_event AS DATE) <= b.month_end
),
databricks_users_month AS (
    SELECT DISTINCT
        email
    FROM
        datalake_databricks.unique_users
    CROSS JOIN bounds AS b
    WHERE
        CAST(dt_created AS DATE) <= b.month_end
        AND (
            dt_deleted IS NULL
            OR CAST(dt_deleted AS DATE) >= b.month_start
        )
),
trino_users_month AS (
    SELECT DISTINCT
        session_user
    FROM
        datalake_trino.query_usage_information
    CROSS JOIN bounds AS b
    WHERE
        MAKE_DATE(year, month, day) >= b.month_start
        AND MAKE_DATE(year, month, day) <= b.month_end
)
SELECT
    COALESCE(e.work_email, dh.user_email) AS user_email,
    e.area_class,
    e.job_class,
    e.business,
    e.product,
    e.vertical,
    e.line,
    e.chapter,
    e.assignment_status_type,
    e.dt_hired,
    e.dt_terminated,
    CASE
        WHEN dh.user_email IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_datahub_user,
    CASE
        WHEN db.email IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_databricks_user,
    CASE
        WHEN tr.session_user IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_trino_user,
    CAST(b.month_start AS DATE) AS dt_reference_month_start,
    CAST(b.month_end AS DATE) AS dt_reference_month_end,
    CASE
        WHEN LOWER('{is_backfilled_dimension_proxy}') = 'true' THEN TRUE
        ELSE FALSE
    END AS is_backfilled_dimension_proxy,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(b.month_start) AS year,
    MONTH(b.month_start) AS month,
    1 AS day
FROM
    bounds AS b
INNER JOIN eligible_employees AS e
    ON TRUE
LEFT JOIN datahub_users_month AS dh
    ON LOWER(TRIM(e.work_email)) = LOWER(TRIM(dh.user_email))
LEFT JOIN databricks_users_month AS db
    ON LOWER(TRIM(e.work_email)) = LOWER(TRIM(db.email))
LEFT JOIN trino_users_month AS tr
    ON LOWER(TRIM(e.work_email)) = LOWER(TRIM(tr.session_user))
