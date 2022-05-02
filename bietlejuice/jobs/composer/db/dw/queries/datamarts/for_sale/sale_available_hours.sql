WITH schedule_aud AS (
	SELECT
	    COALESCE(saud.id_house, ws.id_house) AS id_house,
	    ws.id,
	    TIMESTAMP 'epoch' + ure.ts_revision/1000 *INTERVAL '1 second' as date_time,
    	saud.rev,
		COALESCE(saud.weekday, ws.weekday) AS weekday,
		COALESCE(saud.is_available_between_08_and_09,ws.is_available_between_08_and_09) AS hours_available_08to09,
		COALESCE(saud.is_available_between_09_and_10,ws.is_available_between_09_and_10) AS hours_available_09to10,
		COALESCE(saud.is_available_between_10_and_11,ws.is_available_between_10_and_11) AS hours_available_10to11,
		COALESCE(saud.is_available_between_11_and_12,ws.is_available_between_11_and_12) AS hours_available_11to12,
		COALESCE(saud.is_available_between_12_and_13,ws.is_available_between_12_and_13) AS hours_available_12to13,
		COALESCE(saud.is_available_between_13_and_14,ws.is_available_between_13_and_14) AS hours_available_13to14,
		COALESCE(saud.is_available_between_14_and_15,ws.is_available_between_14_and_15) AS hours_available_14to15,
		COALESCE(saud.is_available_between_15_and_16,ws.is_available_between_15_and_16) AS hours_available_15to16,
		COALESCE(saud.is_available_between_16_and_17,ws.is_available_between_16_and_17) AS hours_available_16to17,
		COALESCE(saud.is_available_between_17_and_18,ws.is_available_between_17_and_18) AS hours_available_17to18,
		COALESCE(saud.is_available_between_18_and_19,ws.is_available_between_18_and_19) AS hours_available_18to19,
		COALESCE(saud.is_available_between_19_and_20,ws.is_available_between_19_and_20) AS hours_available_19to20,
		ws.ts_created,
		ws.ts_updated
	FROM 
	    datalake_ebdb_clean_prod.house_weekly_schedule AS ws
	LEFT JOIN 
	    datalake_ebdb_clean_prod.house_weekly_schedule_aud AS saud
	    	ON saud.id = ws.id
	LEFT JOIN datalake_ebdb_clean_prod.user_revision_entity AS ure
			ON saud.rev = ure.id
	WHERE 
	    COALESCE(saud.weekday, ws.weekday) BETWEEN 1 AND 7
), 
house_default_schedule AS (
    WITH default_schedule_base AS (
        SELECT
            h.id AS id_house,
            h.dt_creation
        FROM 
            datalake_ebdb_clean_prod.house h
        LEFT JOIN 
            schedule_aud AS sa
                ON h.id = sa.id_house
        WHERE
            sa.id_house IS NULL 
    )
    SELECT
        id_house,
        dt_creation,
        1 AS weekday,
        TRUE AS hours_available_08to09,
		TRUE AS hours_available_09to10,
		TRUE AS hours_available_10to11, 
		TRUE AS hours_available_11to12,                  
		TRUE AS hours_available_12to13,
		TRUE AS hours_available_13to14,
		TRUE AS hours_available_14to15,
		TRUE AS hours_available_15to16,
		TRUE AS hours_available_16to17,
		TRUE AS hours_available_17to18,
		TRUE AS hours_available_18to19,
		FALSE AS hours_available_19to20
	FROM 
	    default_schedule_base
	---------------
	UNION ALL
	---------------
    SELECT
        id_house,
        dt_creation,
        2 AS weekday,
        TRUE AS hours_available_08to09,
		TRUE AS hours_available_09to10,
		TRUE AS hours_available_10to11, 
		TRUE AS hours_available_11to12,                  
		TRUE AS hours_available_12to13,
		TRUE AS hours_available_13to14,
		TRUE AS hours_available_14to15,
		TRUE AS hours_available_15to16,
		TRUE AS hours_available_16to17,
		TRUE AS hours_available_17to18,
		TRUE AS hours_available_18to19,
		FALSE AS hours_available_19to20
	FROM 
	    default_schedule_base
	---------------
	UNION ALL
	---------------
    SELECT
        id_house,
        dt_creation,
        3 AS weekday,
        TRUE AS hours_available_08to09,
		TRUE AS hours_available_09to10,
		TRUE AS hours_available_10to11, 
		TRUE AS hours_available_11to12,                  
		TRUE AS hours_available_12to13,
		TRUE AS hours_available_13to14,
		TRUE AS hours_available_14to15,
		TRUE AS hours_available_15to16,
		TRUE AS hours_available_16to17,
		TRUE AS hours_available_17to18,
		TRUE AS hours_available_18to19,
		FALSE AS hours_available_19to20
	FROM 
	    default_schedule_base
	---------------
	UNION ALL
	---------------
    SELECT
        id_house,
        dt_creation,
        4 AS weekday,
        TRUE AS hours_available_08to09,
		TRUE AS hours_available_09to10,
		TRUE AS hours_available_10to11, 
		TRUE AS hours_available_11to12,                  
		TRUE AS hours_available_12to13,
		TRUE AS hours_available_13to14,
		TRUE AS hours_available_14to15,
		TRUE AS hours_available_15to16,
		TRUE AS hours_available_16to17,
		TRUE AS hours_available_17to18,
		TRUE AS hours_available_18to19,
		FALSE AS hours_available_19to20
	FROM 
	    default_schedule_base
	---------------
	UNION ALL
	---------------
    SELECT
        id_house,
        dt_creation,
        5 AS weekday,
        TRUE AS hours_available_08to09,
		TRUE AS hours_available_09to10,
		TRUE AS hours_available_10to11, 
		TRUE AS hours_available_11to12,                  
		TRUE AS hours_available_12to13,
		TRUE AS hours_available_13to14,
		TRUE AS hours_available_14to15,
		TRUE AS hours_available_15to16,
		TRUE AS hours_available_16to17,
		TRUE AS hours_available_17to18,
		TRUE AS hours_available_18to19,
		FALSE AS hours_available_19to20
	FROM 
	    default_schedule_base
	---------------
	UNION ALL
	---------------
    SELECT
        id_house,
        dt_creation,
        6 AS weekday,
        TRUE AS hours_available_08to09,
		TRUE AS hours_available_09to10,
		TRUE AS hours_available_10to11, 
		TRUE AS hours_available_11to12,                  
		TRUE AS hours_available_12to13,
		TRUE AS hours_available_13to14,
		TRUE AS hours_available_14to15,
		TRUE AS hours_available_15to16,
		TRUE AS hours_available_16to17,
		TRUE AS hours_available_17to18,
		TRUE AS hours_available_18to19,
		FALSE AS hours_available_19to20
	FROM 
	    default_schedule_base
	---------------
	UNION ALL
	---------------
    SELECT
        id_house,
        dt_creation,
        7 AS weekday,
        TRUE AS hours_available_08to09,
		TRUE AS hours_available_09to10,
		TRUE AS hours_available_10to11, 
		TRUE AS hours_available_11to12,                  
		TRUE AS hours_available_12to13,
		TRUE AS hours_available_13to14,
		TRUE AS hours_available_14to15,
		TRUE AS hours_available_15to16,
		TRUE AS hours_available_16to17,
		TRUE AS hours_available_17to18,
		TRUE AS hours_available_18to19,
		FALSE AS hours_available_19to20
	FROM 
	    default_schedule_base
), 
house_available_hours AS (
	SELECT
		COALESCE(sa.id_house, hd.id_house) AS id_house,
		COALESCE(sa.date_time, sa.ts_created, hd.dt_creation) AS available_started_date,
		COALESCE(sa.weekday, hd.weekday) AS day_of_week,
		COALESCE(sa.hours_available_08to09, hd.hours_available_08to09, false) AS hours_available_08to09,
		COALESCE(sa.hours_available_09to10, hd.hours_available_09to10, false) AS hours_available_09to10,
		COALESCE(sa.hours_available_10to11, hd.hours_available_10to11, false) AS hours_available_10to11,
		COALESCE(sa.hours_available_11to12, hd.hours_available_11to12, false) AS hours_available_11to12,
		COALESCE(sa.hours_available_12to13, hd.hours_available_12to13, false) AS hours_available_12to13,
		COALESCE(sa.hours_available_13to14, hd.hours_available_13to14, false) AS hours_available_13to14,
		COALESCE(sa.hours_available_14to15, hd.hours_available_14to15, false) AS hours_available_14to15,
		COALESCE(sa.hours_available_15to16, hd.hours_available_15to16, false) AS hours_available_15to16,
		COALESCE(sa.hours_available_16to17, hd.hours_available_16to17, false) AS hours_available_16to17,
		COALESCE(sa.hours_available_17to18, hd.hours_available_17to18, false) AS hours_available_17to18,
		COALESCE(sa.hours_available_18to19, hd.hours_available_18to19, false) AS hours_available_18to19,
		COALESCE(sa.hours_available_19to20, hd.hours_available_19to20, false) AS hours_available_19to20
	FROM 
	    schedule_aud AS sa
	FULL OUTER JOIN 
	    house_default_schedule AS hd
	        ON hd.id_house = sa.id_house
	        AND hd.weekday = sa.weekday
),
sale_listings AS (
    WITH date_aux AS (
        SELECT 
            sk_date,
            date,
            week_start
        FROM 
            dim_date
        WHERE 
            sk_date BETWEEN 20210101 AND CAST(REPLACE(CAST(CURRENT_DATE AS VARCHAR), '-', '') AS BIGINT) - 1 
    )
	SELECT 
        LEFT(f.sk_sale_listing, 9)::BIGINT AS sk_house,
        f.sk_region,
        d.date,
        d.sk_date,
        d.week_start,
        f.status_history,
        ROW_NUMBER() OVER (PARTITION BY f.sk_sale_listing, d.date ORDER BY f.ts_status_started DESC) AS order_status -- daily order status
    FROM 
        sale.fact_listing_status AS f
    JOIN 
        date_aux AS d
            ON TO_CHAR(d.week_start, 'YYYYMMDD')::BIGINT BETWEEN NULLIF(f.sk_status_start_date, -1) 
            AND COALESCE(NULLIF(sk_status_end_date, -1), TO_CHAR(CURRENT_DATE, 'YYYYMMDD')::BIGINT - 1)
	WHERE
		f.status_history IN ('PUBLISHED', 'UNPUBLISHED', 'SUSPENDED')
),
available_hours_week AS (
    WITH hours AS (
        SELECT 
            id_house AS sk_house,
            COALESCE(CAST(TO_CHAR(available_started_date, 'YYYYMMDD') AS bigint),-1) AS sk_available_date,
            day_of_week,
            CASE 
                WHEN id_house IS NOT NULL THEN CASE WHEN hours_available_08to09 IS TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_09to10 IS TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_10to11 IS TRUE THEN 1 ELSE 0 END +
                CASE WHEN hours_available_11to12 IS TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_12to13 IS TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_13to14 IS TRUE THEN 1 ELSE 0 END +
                CASE WHEN hours_available_14to15 IS TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_15to16 IS TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_16to17 IS TRUE THEN 1 ELSE 0 END +
                CASE WHEN hours_available_17to18 IS TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_18to19 IS TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_19to20 IS TRUE THEN 1 ELSE 0 END
            END AS day_hours_available,
            ROW_NUMBER() OVER (PARTITION BY id_house, sk_available_date, day_of_week ORDER BY available_started_date DESC) AS daily_last_status
        FROM 
            house_available_hours 
        )
        SELECT
            sk_house, 
            sk_available_date,
            COALESCE(monday_available_hours, 0) AS monday_available_hours,
            COALESCE(tuesday_available_hours, 0) AS tuesday_available_hours,
            COALESCE(wednesday_available_hours, 0) AS wednesday_available_hours,
            COALESCE(thursday_available_hours, 0) AS thursday_available_hours,
            COALESCE(friday_available_hours, 0) AS friday_available_hours,
            COALESCE(saturday_available_hours, 0) AS saturday_available_hours,
            COALESCE(sunday_available_hours, 0) AS sunday_available_hours
        FROM
            (SELECT 
                * 
            FROM 
                hours 
            WHERE 
                daily_last_status = 1) 
        PIVOT (SUM(day_hours_available) FOR day_of_week IN (1 AS monday_available_hours, 2 AS tuesday_available_hours, 3 AS wednesday_available_hours, 4 AS thursday_available_hours, 5 AS friday_available_hours, 6 AS saturday_available_hours, 7 as sunday_available_hours))
),
aux AS (
    SELECT 
        l.sk_house,
        l.sk_region,
        l.status_history,
        l.date, 
        l.week_start,
        COALESCE(monday_available_hours, LAG(monday_available_hours IGNORE NULLS) OVER (PARTITION BY l.sk_house ORDER BY date)) AS monday_available_hours,
        COALESCE(tuesday_available_hours, LAG(tuesday_available_hours IGNORE NULLS) OVER (PARTITION BY l.sk_house ORDER BY date)) AS tuesday_available_hours,
        COALESCE(wednesday_available_hours, LAG(wednesday_available_hours IGNORE NULLS) OVER (PARTITION BY l.sk_house ORDER BY date)) AS wednesday_available_hours,
        COALESCE(thursday_available_hours, LAG(thursday_available_hours IGNORE NULLS) OVER (PARTITION BY l.sk_house ORDER BY date)) AS thursday_available_hours,
        COALESCE(friday_available_hours, LAG(friday_available_hours IGNORE NULLS) OVER (PARTITION BY l.sk_house ORDER BY date)) AS friday_available_hours,
        COALESCE(saturday_available_hours, LAG(saturday_available_hours IGNORE NULLS) OVER (PARTITION BY l.sk_house ORDER BY date)) AS saturday_available_hours,
        COALESCE(sunday_available_hours, LAG(sunday_available_hours IGNORE NULLS) OVER (PARTITION BY l.sk_house ORDER BY date)) AS sunday_available_hours,
        ah.sk_house IS NOT NULL AS alteration_date
    FROM 
        sale_listings AS l 
    LEFT JOIN 
        available_hours_week AS ah 
            ON l.sk_house = ah.sk_house 
            AND l.sk_date = ah.sk_available_date
	WHERE 
		l.order_status = 1 
)
SELECT 
    sk_house,
    sk_region,
    status_history,
    week_start,
    (monday_available_hours + tuesday_available_hours + wednesday_available_hours + thursday_available_hours + friday_available_hours + saturday_available_hours + sunday_available_hours) AS week_available_hours,
    (monday_available_hours + tuesday_available_hours + wednesday_available_hours + thursday_available_hours + friday_available_hours) AS util_days_available_hours, 
    monday_available_hours,
    tuesday_available_hours,
    wednesday_available_hours,
    thursday_available_hours,
    friday_available_hours,
    saturday_available_hours,
    sunday_available_hours,
    CASE 
        WHEN COUNT(CASE WHEN alteration_date IS TRUE THEN TRUE END) OVER (PARTITION BY sk_house, week_start) = 1 THEN TRUE 
        ELSE FALSE 
    END AS alteration_week, 
    current_timestamp AS ts_load
FROM 
    aux
WHERE 
    1 = 1
    AND monday_available_hours IS NOT NULL 
    AND tuesday_available_hours IS NOT NULL 
    AND wednesday_available_hours IS NOT NULL
    AND thursday_available_hours IS NOT NULL 
    AND friday_available_hours IS NOT NULL 
    AND saturday_available_hours IS NOT NULL
    AND sunday_available_hours IS NOT NULL
    AND DATEPART(YEAR, date) >= 2021 
    AND date = week_start