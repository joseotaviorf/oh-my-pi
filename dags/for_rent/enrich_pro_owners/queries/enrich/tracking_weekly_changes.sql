WITH owner_history_dates AS (
    SELECT
        ohqh.id_owner,
        ohqh.houses,
        ohqh.ts_house_number_started,
        EXPLODE(
            SEQUENCE(
                DATE(ohqh.ts_house_number_started),
                COALESCE(DATE(ohqh.ts_house_number_ended), CURRENT_DATE),
                INTERVAL 1 DAY
            )
        ) AS dt
    FROM
        datalake_pro_owners.owner_houses_quantity_history AS ohqh
    WHERE
        ohqh.houses >= 5
),
houses_by_date AS (
    SELECT
        ohd.id_owner,
        FIRST_VALUE(ohd.houses) OVER(PARTITION BY ohd.dt, ohd.id_owner ORDER BY ohd.ts_house_number_started DESC) AS houses,
        ohd.dt,
        dd.week_end AS dt_week_end,
        ohd.ts_house_number_started,
        MAX(ohd.ts_house_number_started) OVER(PARTITION BY ohd.dt, ohd.id_owner) AS ts_last_started
    FROM
        owner_history_dates AS ohd
    INNER JOIN
        dw_public.dim_date AS dd
            ON dd.date = ohd.dt
)
SELECT
    id_owner,
    houses,
    dt_week_end,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    houses_by_date
WHERE
    ts_house_number_started = ts_last_started
    AND dt = dt_week_end
