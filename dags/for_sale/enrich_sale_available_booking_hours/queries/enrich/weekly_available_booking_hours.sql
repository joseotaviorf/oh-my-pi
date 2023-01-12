WITH sale_listings AS (
    SELECT 
        lbc.id_house,
        h.id_region,
        lbc.ts_created
    FROM 
        datalake_ebdb_clean.listing_business_context AS lbc
    LEFT JOIN 
        datalake_ebdb_clean.house AS h
            ON h.id = lbc.id_house
    WHERE
        business_context = 'SALE'
),
aux_schedule_aud AS (
    SELECT 
        hah.id_house, 
        sl.id_region,
        hah.dt_available_started AS date,
        monday_available_hours,
        tuesday_available_hours,
        wednesday_available_hours,
        thursday_available_hours,
        friday_available_hours,
        saturday_available_hours,
        sunday_available_hours
    FROM 
        datalake_booking.house_available_hours AS hah
    INNER JOIN
        sale_listings AS sl
            ON hah.id_house = sl.id_house
    PIVOT (
        SUM(hah.day_hours_available) 
    FOR 
        day_of_week 
        IN (1 AS monday_available_hours, 
            2 AS tuesday_available_hours, 
            3 AS wednesday_available_hours, 
            4 AS thursday_available_hours, 
            5 AS friday_available_hours, 
            6 AS saturday_available_hours, 
            7 AS sunday_available_hours))
),
schedule_aud AS (
    SELECT 
        id_house,
        id_region,
        date,
        SUM(monday_available_hours) AS monday_available_hours,
        SUM(tuesday_available_hours) AS tuesday_available_hours,
        SUM(wednesday_available_hours) AS wednesday_available_hours,
        SUM(thursday_available_hours) AS thursday_available_hours,
        SUM(friday_available_hours) AS friday_available_hours,
        SUM(saturday_available_hours) AS saturday_available_hours,
        SUM(sunday_available_hours) AS sunday_available_hours
    FROM
        aux_schedule_aud
    GROUP BY
        1, 2, 3
),
schedule_changes AS (
    SELECT 
        id_house,
        id_region,
        date,
        LAST_VALUE(monday_available_hours, TRUE) OVER (PARTITION BY id_house ORDER BY date ASC) AS monday_available_hours, 
        LAST_VALUE(tuesday_available_hours, TRUE) OVER (PARTITION BY id_house ORDER BY date ASC) AS tuesday_available_hours,
        LAST_VALUE(wednesday_available_hours, TRUE) OVER (PARTITION BY id_house ORDER BY date ASC) AS wednesday_available_hours,
        LAST_VALUE(thursday_available_hours, TRUE) OVER (PARTITION BY id_house ORDER BY date ASC) AS thursday_available_hours,
        LAST_VALUE(friday_available_hours, TRUE) OVER (PARTITION BY id_house ORDER BY date ASC) AS friday_available_hours,
        LAST_VALUE(saturday_available_hours, TRUE) OVER (PARTITION BY id_house ORDER BY date ASC) AS saturday_available_hours,
        LAST_VALUE(sunday_available_hours, TRUE) OVER (PARTITION BY id_house ORDER BY date ASC) AS sunday_available_hours
    FROM
        schedule_aud
),
aux AS (
    SELECT 
        id_house,
        id_region,
        (
            monday_available_hours + 
            tuesday_available_hours + 
            wednesday_available_hours + 
            thursday_available_hours + 
            friday_available_hours + 
            saturday_available_hours + 
            sunday_available_hours
        ) 
        AS week_available_hours,
        (
            monday_available_hours + 
            tuesday_available_hours + 
            wednesday_available_hours +
            thursday_available_hours + 
            friday_available_hours
        ) 
        AS workdays_available_hours, 
        monday_available_hours,
        tuesday_available_hours,
        wednesday_available_hours,
        thursday_available_hours,
        friday_available_hours,
        saturday_available_hours,
        sunday_available_hours,
        CAST(date AS DATE) AS dt_schedule_started,
        LEAD(CAST(date AS DATE)) OVER (PARTITION BY id_house ORDER BY date) AS dt_schedule_ended
    FROM
        schedule_changes
)
SELECT
    id_house,
    id_region,
    week_available_hours,
    workdays_available_hours,
    monday_available_hours,
    tuesday_available_hours,
    wednesday_available_hours,
    thursday_available_hours,
    friday_available_hours,
    saturday_available_hours,
    sunday_available_hours,
    dt_schedule_started,
    dt_schedule_ended
FROM 
   aux