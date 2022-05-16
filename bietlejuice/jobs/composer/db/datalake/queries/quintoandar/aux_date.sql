/*
This table has the same goal (and columns) of the dim_date, but will be available in datalake for potential use in enriches.
SPARK 3.x is necessary (YEAROFWEEK is necessary to get the year related to week and it is only 
                        available in SPARK >= 3.0)

*/

WITH base_date AS (
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
                                    WHEN DATE_FORMAT(dt, 'MMdd') IN ('0101', '0421', '0501', '0907', '1012', '1102', '1115', '1225') THEN 'Holiday' 
                                    ELSE 'No holiday' 
                                END) = 'Holiday') THEN 0 
                    ELSE 1 
                END
            ) OVER(PARTITION BY date_trunc('month',dt) ORDER BY DAY(dt) ROWS UNBOUNDED PRECEDING) AS working_days_in_month,
        -- Fixed holidays
        CASE 
            WHEN DATE_FORMAT(dt, 'MMdd') IN ('0101', '0421', '0501', '0907', '1012', '1102', '1115', '1225') THEN 'Holiday'
            ELSE 'No holiday' 
        END AS is_brz_holiday,
        dt AS date,
        DATE_FORMAT(dt, 'dd/MM/yyyy') AS brz_date,
        DATE_FORMAT(dt, 'MM/dd/yyyy') AS usa_date,
        DATE_FORMAT(dt, 'yyyy/MM/dd') AS universal_date,
        DATE_TRUNC('week',dt) AS week_start,
        DATE_TRUNC('week',dt) + INTERVAL 1 WEEK - INTERVAL 1 DAY AS week_end,
        DATE_TRUNC('month',dt) AS month_start,
        DATE_TRUNC('month',dt) + INTERVAL 1 MONTH - INTERVAL 1 DAY AS month_end,
        dt - INTERVAL 1 DAY AS last_day,
        dt - INTERVAL 7 DAY AS last_week,
        dt - INTERVAL 14 DAY AS last_2_weeks,
        dt - INTERVAL 28 DAY AS last_4_weeks,
        dt - INTERVAL 1 MONTH AS last_month,
        dt - INTERVAL 3 MONTH AS last_quarter,
        dt - INTERVAL 1 YEAR AS last_year
  FROM (
      -- There are 3 leap years in this range, so calculate 365 * 10 + 3 records
      SELECT 
          dt
      FROM
          VALUES(SEQUENCE(DATE('2010-01-01'),DATE('2031-12-31'), INTERVAL 1 DAY)) AS t1(date_array)
          LATERAL VIEW EXPLODE(date_array) AS dt
       ) DQ
  ORDER BY 1
)
SELECT
    id_date,
    day,
    day_of_year,
    week_day,
    weekday_name,
    calendar_week,
    weekend,
    month,
    month_name,
    quarter,
    brz_season,
    year,
    year_calendar_week,
    year_month,
    year_quarter,
    working_days_in_month,
    MAX(working_days_in_month) OVER (PARTITION BY year, month) AS total_working_days_in_month,
    is_brz_holiday,
    date,
    brz_date,
    usa_date,
    universal_date,
    DATE(week_start) AS week_start,
    DATE(week_end) AS week_end,
    DATE(month_start) AS month_start,
    DATE(month_end) AS month_end,
    last_day,
    last_week,
    last_2_weeks,
    last_4_weeks,
    last_month,
    last_quarter,
    last_year
FROM
    base_date
UNION ALL
SELECT
    -1 AS id_date,
    NULL AS day,
    NULL AS day_of_year,
    NULL AS week_day,
    NULL AS weekday_name,
    NULL AS calendar_week,
    NULL AS weekend,
    NULL AS month,
    NULL AS month_name,
    NULL AS quarter,
    NULL AS brz_season,
    NULL AS year,
    NULL AS year_calendar_week,
    NULL AS year_month,
    NULL AS year_quarter,
    1 AS working_days_in_month,
    1 AS total_working_days_in_month,
    NULL AS is_brz_holiday,
    NULL AS date,
    NULL AS brz_date,
    NULL AS usa_date,
    NULL AS universal_date,
    NULL AS week_start,
    NULL AS week_end,
    NULL AS month_start,
    NULL AS month_end,
    NULL AS last_day,
    NULL AS last_week,
    NULL AS last_2_weeks,
    NULL AS last_4_weeks,
    NULL AS last_month,
    NULL AS last_quarter,
    NULL AS last_year