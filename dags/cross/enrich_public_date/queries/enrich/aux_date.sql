/*
This table has the same goal (and columns) of the dim_date, but will be available in datalake for potential use in enriches.
SPARK 3.x is necessary (YEAROFWEEK is necessary to get the year related to week and it is only
                        available in SPARK >= 3.0)

*/

WITH
mexican_holidays AS (
    SELECT
        holiday_name,
        holiday_category,
        holiday_name,
        dt_holiday_start
    FROM datalake_google_calendar_clean.mexican_holidays
    QUALIFY ROW_NUMBER() OVER(PARTITION BY dt_holiday_start, dt_holiday_end ORDER BY ts_updated DESC) = 1
),
brazillian_holidays AS (
    SELECT
        holiday_name,
        holiday_category,
        holiday_name,
        dt_holiday_start
    FROM datalake_google_calendar_clean.brazillian_holidays
    QUALIFY ROW_NUMBER() OVER(PARTITION BY dt_holiday_start, dt_holiday_end ORDER BY ts_updated DESC) = 1
),
month_to_bimester AS (
    SELECT 
        *
    FROM (
        VALUES
            (1, 1, 'Jan/Feb', ARRAY(1, 2)),
            (2, 1, 'Jan/Feb', ARRAY(1, 2)),
            (3, 2, 'Mar/Apr', ARRAY(3, 4)),
            (4, 2, 'Mar/Apr', ARRAY(3, 4)),
            (5, 3, 'May/Jun', ARRAY(5, 6)),
            (6, 3, 'May/Jun', ARRAY(5, 6)),
            (7, 4, 'Jul/Aug', ARRAY(7, 8)),
            (8, 4, 'Jul/Aug', ARRAY(7, 8)),
            (9, 5, 'Sep/Oct', ARRAY(9, 10)),
            (10, 5, 'Sep/Oct', ARRAY(9, 10)),
            (11, 6, 'Nov/Dec', ARRAY(11, 12)),
            (12, 6, 'Nov/Dec', ARRAY(11, 12))
    ) AS t(month, bimester, bimester_name, bimester_months)
),
base_date AS (
    SELECT
        CAST(REPLACE(dt, '-','') AS BIGINT) AS id_date,
        DAY(dt) AS day,
        DATE_FORMAT(dt, 'D') AS day_of_year,
        DAYOFWEEK(dt) -1  AS week_day,
        DATE_FORMAT(dt, 'EEEE') AS weekday_name,
        WEEKOFYEAR(dt) AS calendar_week,
        CASE
            WHEN DAYOFWEEK(dt) IN (1, 7) THEN 'Weekend'
            ELSE 'Weekday'
        END AS weekend,
        MONTH(dt) AS month,
        DATE_FORMAT(dt, 'MMMM') AS month_name,
        mtb.bimester,
        mtb.bimester_name,
        mtb.bimester_months,
        'Q' || QUARTER(dt) AS quarter,
        CASE
            WHEN DATE_FORMAT(dt, 'MMdd') BETWEEN '0320' AND '0619' THEN 'Autumn'
            WHEN DATE_FORMAT(dt, 'MMdd') BETWEEN '0620' AND '0921' THEN 'Winter'
            WHEN DATE_FORMAT(dt, 'MMdd') BETWEEN '0922' AND '1220' THEN 'Spring'
            ELSE 'Summer'
        END AS brz_Season,
        YEAR(dt) AS year,
        EXTRACT(YEAROFWEEK FROM dt) || '/' || WEEKOFYEAR(dt) AS year_calendar_week,
        DATE_FORMAT(dt, 'yyyy/MM') AS year_month,
        YEAR(dt) ||  '/Q' || QUARTER(dt) AS year_quarter,
        SUM(
                CASE
                    WHEN ((CASE
                            WHEN DAYOFWEEK(dt) IN (1, 7) THEN 'Weekend'
                            ELSE 'Weekday'
                            END) = 'Weekend'
                            OR (CASE
                                    WHEN DATE_FORMAT(dt, 'MMdd') IN ('0101', '0421', '0501', '0907', '1012', '1102', '1115', '1225') OR is_br_holliday IS TRUE THEN 'Holiday'
                                    ELSE 'No holiday'
                                END) = 'Holiday') THEN 0
                    ELSE 1
                END
            ) OVER(PARTITION BY date_trunc('month',dt) ORDER BY DAY(dt) ROWS UNBOUNDED PRECEDING) AS working_days_in_month,
        SUM(
                CASE
                    WHEN ((CASE
                            WHEN DAYOFWEEK(dt) IN (1, 7) THEN 'Weekend'
                            ELSE 'Weekday'
                            END) = 'Weekend'
                            OR (CASE
                                    WHEN LOWER(br_holiday_name) LIKE "%carnival end (until 2pm)%" THEN 'No holiday'
                                    WHEN LOWER(br_holiday_name) LIKE "%black awareness day%" THEN 'No holiday'
                                    WHEN LOWER(br_holiday_name) LIKE "%christmas eve (from 2pm)" THEN 'No holiday'
                                    WHEN DATE_FORMAT(dt, 'MMdd') IN ('0101', '0421', '0501', '0907', '1012', '1102', '1115', '1225') OR is_br_holliday IS TRUE THEN 'Holiday'
                                    ELSE 'No holiday'
                                END) = 'Holiday') THEN 0
                    ELSE 1
                END
            ) OVER(PARTITION BY date_trunc('month',dt) ORDER BY DAY(dt) ROWS UNBOUNDED PRECEDING) AS working_days_in_month_fintech,
        -- Fixed holidays + Dinamic days
        CASE
            WHEN DATE_FORMAT(dt, 'MMdd') IN ('0101', '0421', '0501', '0907', '1012', '1102', '1115', '1225') OR is_br_holliday IS TRUE THEN 'Holiday'
            ELSE 'No holiday'
        END AS is_brz_holiday,
        CASE
            WHEN LOWER(br_holiday_name) LIKE "%carnival end (until 2pm)%" THEN 'No holiday'
            WHEN LOWER(br_holiday_name) LIKE "%black awareness day%" THEN 'No holiday'
            WHEN LOWER(br_holiday_name) LIKE "%christmas eve (from 2pm)" THEN 'No holiday'
            WHEN DATE_FORMAT(dt, 'MMdd') IN ('0101', '0421', '0501', '0907', '1012', '1102', '1115', '1225') OR is_br_holliday IS TRUE THEN 'Holiday'
            ELSE 'No holiday'
        END AS is_brz_fintech_holiday,
        br_holiday_name,
        -- Fixed holidays + Dinamic days
        CASE
            WHEN is_mx_holliday IS TRUE THEN 'Holiday'
            ELSE 'No holiday'
        END AS is_mx_holiday,
        mx_holiday_name,
        dt AS date,
        DATE_FORMAT(dt, 'dd/MM/yyyy') AS brz_date,
        DATE_FORMAT(dt, 'MM/dd/yyyy') AS usa_date,
        DATE_FORMAT(dt, 'yyyy/MM/dd') AS universal_date,
        DATE_TRUNC('week',dt) AS week_start,
        DATE_TRUNC('week',dt) + INTERVAL 1 WEEK - INTERVAL 1 DAY AS week_end,
        DATE_TRUNC('month',dt) AS month_start,
        DATE_TRUNC('month',dt) + INTERVAL 1 MONTH - INTERVAL 1 DAY AS month_end,
        MAKE_DATE(YEAR(dt), mtb.bimester_months[0], 1) AS bimester_start,
        LAST_DAY(MAKE_DATE(YEAR(dt), mtb.bimester_months[1], 1)) AS bimester_end,
        dt - INTERVAL 1 DAY AS last_day,
        dt - INTERVAL 7 DAY AS last_week,
        dt - INTERVAL 14 DAY AS last_2_weeks,
        dt - INTERVAL 28 DAY AS last_4_weeks,
        dt - INTERVAL 1 MONTH AS last_month,
        dt - INTERVAL 3 MONTH AS last_quarter,
        dt - INTERVAL 1 YEAR AS last_year
    FROM (
        SELECT
            dt,
            bz.holiday_name AS br_holiday_name,
            IF(bz.dt_holiday_start IS NOT NULL, TRUE, FALSE) AS is_br_holliday,
            mx.holiday_name AS mx_holiday_name,
            IF(mx.dt_holiday_start IS NOT NULL OR mx.holiday_name like 'Revolution Day%' OR bz.holiday_name like 'Good Friday%', TRUE, FALSE) AS is_mx_holliday
        FROM
        (
            -- There are 3 leap years in this range, so calculate 365 * 10 + 3 records
            SELECT
                dt
            FROM
                VALUES(SEQUENCE(DATE('2010-01-01'),DATE('2031-12-31'), INTERVAL 1 DAY)) AS t1(date_array)
                LATERAL VIEW EXPLODE(date_array) AS dt
        ) DQ

        LEFT JOIN
            brazillian_holidays AS bz
                ON dt = bz.dt_holiday_start
                AND bz.holiday_category = "Public holiday"
                AND bz.holiday_name <> 'Public Service Holiday'
        LEFT JOIN
            mexican_holidays AS mx
                ON dt = mx.dt_holiday_start
                AND (mx.holiday_category = "Public holiday" OR mx.holiday_name like 'Revolution Day%')

    ) AS d
    JOIN
        month_to_bimester AS mtb
            ON MONTH(d.dt) = mtb.month
    ORDER BY 1
)
SELECT DISTINCT
    id_date,
    day,
    day_of_year,
    week_day,
    weekday_name,
    calendar_week,
    weekend,
    month,
    month_name,
    bimester,
    bimester_name,
    bimester_months,
    quarter,
    brz_season,
    year,
    year_calendar_week,
    year_month,
    year_quarter,
    working_days_in_month,
    working_days_in_month_fintech,
    MAX(working_days_in_month) OVER (PARTITION BY year, month) AS total_working_days_in_month,
    MAX(working_days_in_month_fintech) OVER (PARTITION BY year, month) AS total_working_days_in_month_fintech,
    is_brz_holiday,
    is_brz_fintech_holiday,
    br_holiday_name,
    IF(weekend = "Weekday" AND is_brz_holiday = "No holiday", TRUE, FALSE) is_brz_business_day,
    IF(weekend = "Weekday" AND is_brz_fintech_holiday = "No holiday", TRUE, FALSE) is_brz_fintech_business_day,
    LEAD(IF(weekend = "Weekday" AND is_brz_holiday = "No holiday", date, NULL)) IGNORE NULLS OVER (ORDER BY DATE(date) ASC) next_brz_business_day,
    LEAD(IF(weekend = "Weekday" AND is_brz_fintech_holiday = "No holiday", date, NULL)) IGNORE NULLS OVER (ORDER BY DATE(date) ASC) next_brz_fintech_business_day,
    is_mx_holiday,
    mx_holiday_name,
    date,
    brz_date,
    usa_date,
    universal_date,
    DATE(week_start) AS week_start,
    DATE(week_end) AS week_end,
    DATE(month_start) AS month_start,
    DATE(month_end) AS month_end,
    DATE(bimester_start) AS bimester_start,
    DATE(bimester_end) AS bimester_end,
    last_day,
    last_week,
    last_2_weeks,
    last_4_weeks,
    last_month,
    last_quarter,
    last_year
FROM
    base_date