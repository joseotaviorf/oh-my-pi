WITH snapshot AS (
    SELECT 
        d.sk_date,
        w.id_house AS sk_house,
        w.id_region AS sk_region,
        w.week_available_hours,
        w.workdays_available_hours,
        w.monday_available_hours,
        w.tuesday_available_hours,
        w.wednesday_available_hours,
        w.thursday_available_hours,
        w.friday_available_hours,
        w.saturday_available_hours,
        w.sunday_available_hours,
        d.year,
        d.month,
        d.day
    FROM 
        datalake_sale_available_booking_hours.weekly_available_booking_hours AS w
    JOIN
        dw_public.dim_date AS d
            ON d.date BETWEEN w.dt_schedule_started AND COALESCE(w.dt_schedule_ended, NOW())
    WHERE        
        MAKE_DATE(d.year, d.month, d.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY sk_house, year, month, day ORDER BY dt_schedule_started DESC) = 1
),
sale_status AS (
    SELECT 
        CAST(LEFT(f.sk_sale_listing, 9) AS BIGINT) AS sk_house,
        f.sk_region,
        f.status_history,
        d.year,
        d.month,
        d.day
    FROM 
        dw_sale.fact_listing_status AS f
    JOIN 
        dw_public.dim_date AS d
            ON d.date BETWEEN DATE(f.ts_status_started) AND COALESCE(DATE(f.ts_status_ended), NOW())
    WHERE        
        MAKE_DATE(d.year, d.month, d.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY f.sk_sale_listing, d.date ORDER BY f.ts_status_started DESC) = 1
)
SELECT
    sk_date,
    sk_house,
    COALESCE(s.sk_region, sst.sk_region) AS sk_region,
    status_history,
    week_available_hours,
    workdays_available_hours,
    monday_available_hours,
    tuesday_available_hours,
    wednesday_available_hours,
    thursday_available_hours,
    friday_available_hours,
    saturday_available_hours,
    sunday_available_hours,
    year,
    month,
    day
FROM
    snapshot AS s
LEFT JOIN 
    sale_status AS sst
        USING(sk_house, day, month, year)
WHERE
    status_history IS NOT NULL