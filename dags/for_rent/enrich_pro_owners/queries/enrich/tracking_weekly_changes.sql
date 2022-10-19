WITH houses_by_date AS (
    SELECT 
        id_owner,
        FIRST_VALUE(houses) OVER(PARTITION BY dd.date,id_owner ORDER BY ts_house_number_started DESC) AS houses,
        dd.date AS dt,
        dd.week_end AS dt_week_end,
        ts_house_number_started,
        MAX(ts_house_number_started) OVER(PARTITION BY dd.date, id_owner)AS ts_last_started
    FROM
        datalake_pro_owners.owner_houses_quantity_history AS ohqh
    JOIN
        dw_public.dim_date AS dd
            ON dd.date BETWEEN DATE(ohqh.ts_house_number_started) AND COALESCE(DATE(ohqh.ts_house_number_ended), CURRENT_DATE)
    WHERE
        houses >= 5
)
SELECT
    id_owner,
    houses,
    dt_week_end,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    houses_by_date
WHERE
    ts_house_number_started = ts_last_started
    AND dt = dt_week_end 