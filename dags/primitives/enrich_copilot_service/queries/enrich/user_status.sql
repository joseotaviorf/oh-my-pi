WITH
user_session AS (
    SELECT
        id_user,
        id AS id_session,
        MIN(ts_created) AS ts_session_created,
        MIN(MIN(ts_created)) OVER(PARTITION BY id_user) AS ts_first_session_created
    FROM
        datalake_copilot_service_clean.session
    GROUP BY
        1, 2
),
offset_dates AS (
    SELECT
        id_user,
        id_session,
        ts_session_created,
        ts_first_session_created,
        LEAD(ts_session_created) OVER(PARTITION BY id_user ORDER BY ts_session_created) AS ts_next_session_created
    FROM
        user_session
),
churn_dates AS (
    SELECT
        id_user,
        ts_session_created,
        ts_first_session_created,
        ts_next_session_created,
        CASE 
            WHEN DATEDIFF(DAY, ts_session_created, COALESCE(ts_next_session_created, NOW())) > 7
            THEN DATEADD(DAY, 7, ts_session_created)
        END AS ts_churn
    FROM
        offset_dates
),
next_churn_dates AS (
    SELECT
        id_user,
        ts_session_created,
        ts_first_session_created,
        ts_next_session_created,
        ts_churn,
        FIRST(ts_churn) IGNORE NULLS OVER(
          PARTITION BY id_user
          ORDER BY ts_session_created
          ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
        ) AS ts_next_churn
    FROM
        churn_dates
    GROUP BY
        1, 2, 3, 4, 5
),
churned_periods AS (
    SELECT
        id_user,
        ts_churn AS ts_status_start,
        ts_next_session_created AS ts_status_end,
        ts_first_session_created,
        'INACTIVE' AS status
    FROM
        next_churn_dates
    WHERE
        ts_churn IS NOT NULL
),
active_periods AS (
    SELECT
        id_user,
        MIN(ts_session_created) AS ts_status_start,
        ts_next_churn AS ts_status_end,
        ts_first_session_created,
        'ACTIVE' AS status
    FROM 
        next_churn_dates
    GROUP BY
        1, 3, 4, 5
),
agregated_status AS (
    SELECT * FROM churned_periods
    UNION ALL
    SELECT * FROM active_periods
)
SELECT
    id_user,
    ts_status_start,
    ts_status_end,
    status,
    CASE
        WHEN status = 'ACTIVE' AND ts_status_start = ts_first_session_created
            THEN 'new'
        WHEN status = 'ACTIVE' AND ts_status_start > ts_first_session_created
            THEN 'reactivated'
        ELSE NULL
    END AS status_detail,
    CASE
        WHEN ts_status_end IS NULL THEN TRUE
        ELSE FALSE
    END AS is_current_status,
    ROW_NUMBER() OVER(PARTITION BY id_user, DATE(ts_status_start) ORDER BY ts_status_start DESC) = 1 AS is_last_status_of_the_day
FROM
    agregated_status