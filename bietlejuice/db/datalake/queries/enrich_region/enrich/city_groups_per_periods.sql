WITH dimension_period AS (
    SELECT DISTINCT
        year,
        month_start AS dt_month_started,
        week_start AS dt_week_started
    FROM 
        datalake_quintoandar.aux_date
    WHERE
        date BETWEEN DATE('2019-01-01') AND DATE_ADD(CURRENT_DATE, 30)

),
dimension_region AS (
  SELECT DISTINCT
    city_group,
    country_code,
    country_name
  FROM 
    datalake_region.region
)
SELECT
    country_code,
    country_name,
    city_group,
    year,
    dt_month_started,
    dt_week_started
FROM 
    dimension_period
CROSS JOIN 
    dimension_region