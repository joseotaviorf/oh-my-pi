WITH schedule_aud AS (
	SELECT
	    COALESCE(saud.id_house, ws.id_house) AS id_house,
	    ws.id,
        FROM_UNIXTIME(ure.ts_revision/1000) AS date_time,
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
        FALSE AS is_default_schedule,
		ws.ts_created,
		ws.ts_updated
	FROM 
	    datalake_ebdb_clean.house_weekly_schedule AS ws
	LEFT JOIN 
	    datalake_ebdb_clean.house_weekly_schedule_aud AS saud
	    	ON saud.id = ws.id
	LEFT JOIN datalake_ebdb_clean.user_revision_entity AS ure
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
            datalake_ebdb_clean.house h
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
		FALSE AS hours_available_19to20,
        TRUE AS is_default_schedule
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
		FALSE AS hours_available_19to20,
        TRUE AS is_default_schedule
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
		FALSE AS hours_available_19to20,
        TRUE AS is_default_schedule
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
		FALSE AS hours_available_19to20,
        TRUE AS is_default_schedule
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
		FALSE AS hours_available_19to20,
        TRUE AS is_default_schedule
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
		FALSE AS hours_available_17to18,
		FALSE AS hours_available_18to19,
		FALSE AS hours_available_19to20,
        TRUE AS is_default_schedule
	FROM 
	    default_schedule_base
	---------------
	UNION ALL
	---------------
    SELECT
        id_house,
        dt_creation,
        7 AS weekday,
        FALSE AS hours_available_08to09,
		FALSE AS hours_available_09to10,
		FALSE AS hours_available_10to11, 
		FALSE AS hours_available_11to12,                  
		FALSE AS hours_available_12to13,
		FALSE AS hours_available_13to14,
		FALSE AS hours_available_14to15,
		FALSE AS hours_available_15to16,
		FALSE AS hours_available_16to17,
		FALSE AS hours_available_17to18,
		FALSE AS hours_available_18to19,
		FALSE AS hours_available_19to20,
        TRUE AS is_default_schedule
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
		COALESCE(sa.hours_available_19to20, hd.hours_available_19to20, false) AS hours_available_19to20,
        COALESCE(sa.is_default_schedule, hd.is_default_schedule, false) AS is_default_schedule
	FROM 
	    schedule_aud AS sa
	FULL OUTER JOIN 
	    house_default_schedule AS hd
	        ON hd.id_house = sa.id_house
	        AND hd.weekday = sa.weekday
),
available_hours_week AS (
  WITH hours AS (
      SELECT 
          id_house AS sk_house,
          CAST(REGEXP_REPLACE(LEFT(CAST(available_started_date AS STRING), 10), '-', '') AS BIGINT) AS sk_available_date,
          available_started_date,
          day_of_week,
          CASE 
              WHEN id_house IS NOT NULL THEN CASE WHEN hours_available_08to09 = TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_09to10 = TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_10to11 = TRUE THEN 1 ELSE 0 END +
              CASE WHEN hours_available_11to12 = TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_12to13 = TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_13to14 = TRUE THEN 1 ELSE 0 END +
              CASE WHEN hours_available_14to15 = TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_15to16 = TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_16to17 = TRUE THEN 1 ELSE 0 END +
              CASE WHEN hours_available_17to18 = TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_18to19 = TRUE THEN 1 ELSE 0 END + CASE WHEN hours_available_19to20 = TRUE THEN 1 ELSE 0 END
          END AS day_hours_available,
          is_default_schedule,
          ROW_NUMBER() OVER (PARTITION BY id_house, CAST(REGEXP_REPLACE(LEFT(CAST(available_started_date AS STRING), 10), '-', '') AS BIGINT), day_of_week ORDER BY available_started_date DESC) AS daily_last_status
      FROM 
          house_available_hours 
   ),
   pivoting_hours AS (
      SELECT 
          sk_house, 
          sk_available_date,
          available_started_date,
          daily_last_status,
          is_default_schedule,
          CASE 
              WHEN ROW_NUMBER() OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) = 1 THEN COALESCE(monday_available_hours, 0)
              ELSE monday_available_hours 
          END AS monday_available_hours,
          CASE 
              WHEN ROW_NUMBER() OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) = 1 THEN COALESCE(tuesday_available_hours, 0)
              ELSE tuesday_available_hours 
          END AS tuesday_available_hours,
          CASE 
              WHEN ROW_NUMBER() OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) = 1 THEN COALESCE(wednesday_available_hours, 0)
              ELSE wednesday_available_hours 
          END AS wednesday_available_hours,
          CASE 
              WHEN ROW_NUMBER() OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) = 1 THEN COALESCE(thursday_available_hours, 0)
              ELSE thursday_available_hours 
          END AS thursday_available_hours,
          CASE 
              WHEN ROW_NUMBER() OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) = 1 THEN COALESCE(friday_available_hours, 0)
              ELSE friday_available_hours 
          END AS friday_available_hours,
          CASE 
              WHEN ROW_NUMBER() OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) = 1 THEN COALESCE(saturday_available_hours, 0)
              ELSE saturday_available_hours 
          END AS saturday_available_hours,
          CASE 
              WHEN ROW_NUMBER() OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) = 1 THEN COALESCE(sunday_available_hours, 0)
              ELSE sunday_available_hours 
          END AS sunday_available_hours
       FROM
          hours 
       PIVOT (
           SUM(day_hours_available) 
       FOR 
         day_of_week 
             IN (1 AS monday_available_hours, 
                 2 AS tuesday_available_hours, 
                 3 AS wednesday_available_hours, 
                 4 AS thursday_available_hours, 
                 5 AS friday_available_hours, 
                 6 AS saturday_available_hours, 
                 7 AS sunday_available_hours))
        WHERE 
          daily_last_status = 1
   )
   SELECT
        sk_house,
        sk_available_date AS sk_date,
        available_started_date,
        LAST_VALUE(monday_available_hours, TRUE) OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) AS monday_available_hours, 
        LAST_VALUE(tuesday_available_hours, TRUE) OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) AS tuesday_available_hours, 
        LAST_VALUE(wednesday_available_hours, TRUE) OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) AS wednesday_available_hours, 
        LAST_VALUE(thursday_available_hours, TRUE) OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) AS thursday_available_hours, 
        LAST_VALUE(friday_available_hours, TRUE) OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) AS friday_available_hours, 
        LAST_VALUE(saturday_available_hours, TRUE) OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) AS saturday_available_hours, 
        LAST_VALUE(sunday_available_hours, TRUE) OVER (PARTITION BY sk_house ORDER BY available_started_date ASC) AS sunday_available_hours,
        is_default_schedule,
        ROW_NUMBER() OVER (PARTITION BY sk_house, sk_available_date ORDER BY available_started_date DESC) AS order_day_status
    FROM 
      pivoting_hours
),
timeline AS (
  WITH aux_timeline AS (
    SELECT 
      sk_house,
      MIN(sk_date) AS dt_first_alteration
    FROM 
        available_hours_week
    GROUP BY 
      1
   )
   SELECT 
     d.sk_date,
     sk_house
   FROM 
       aux_timeline AS t
   LEFT JOIN
       dw_public.dim_date AS d
           ON d.sk_date BETWEEN NULLIF(t.dt_first_alteration,-1) AND (CAST(REPLACE(CAST(current_date AS STRING), '-', '') AS BIGINT) - 1)
),
sale_listings AS (
	SELECT 
        CAST(LEFT(f.sk_sale_listing, 9) AS BIGINT) AS sk_house,
        d.date,
        d.sk_date,
        d.week_start,
        f.status_history,
        ROW_NUMBER() OVER (PARTITION BY f.sk_sale_listing, d.date ORDER BY f.ts_status_started DESC) AS order_status -- daily order status
    FROM 
        dw_sale.fact_listing_status AS f
    JOIN 
        dw_public.dim_date AS d
            ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date, -1)
            AND COALESCE(NULLIF(sk_status_end_date, -1), CAST(REGEXP_REPLACE(CAST(CURRENT_DATE AS STRING), '-', '') AS BIGINT))
	WHERE
		f.status_history IN ('PUBLISHED', 'UNPUBLISHED', 'SUSPENDED')
),
aux AS (
    SELECT 
        t.sk_house,
        t.sk_date,
        f.sk_region,
        COALESCE(s.date, d.date) AS date,
        COALESCE(s.week_start, d.week_start) AS week_start,
        ah.available_started_date, 
        COALESCE(s.status_history, 'UNPUBLISHED IN SALE') AS status_history,
        LAST_VALUE(monday_available_hours, TRUE) OVER (PARTITION BY t.sk_house ORDER BY t.sk_date ASC) AS monday_available_hours, 
        LAST_VALUE(tuesday_available_hours, TRUE) OVER (PARTITION BY t.sk_house ORDER BY t.sk_date ASC) AS tuesday_available_hours, 
        LAST_VALUE(wednesday_available_hours, TRUE) OVER (PARTITION BY t.sk_house ORDER BY t.sk_date ASC) AS wednesday_available_hours, 
        LAST_VALUE(thursday_available_hours, TRUE) OVER (PARTITION BY t.sk_house ORDER BY t.sk_date ASC) AS thursday_available_hours, 
        LAST_VALUE(friday_available_hours, TRUE) OVER (PARTITION BY t.sk_house ORDER BY t.sk_date ASC) AS friday_available_hours, 
        LAST_VALUE(saturday_available_hours, TRUE) OVER (PARTITION BY t.sk_house ORDER BY t.sk_date ASC) AS saturday_available_hours, 
        LAST_VALUE(sunday_available_hours, TRUE) OVER (PARTITION BY t.sk_house ORDER BY t.sk_date ASC) AS sunday_available_hours,
        CASE 
            WHEN COUNT(CASE WHEN ah.available_started_date IS NOT NULL THEN TRUE END) OVER (PARTITION BY t.sk_house, COALESCE(s.week_start, d.week_start)) = 1 THEN TRUE 
            ELSE FALSE 
        END AS alteration_week,
        LAST_VALUE(is_default_schedule, TRUE) OVER (PARTITION BY t.sk_house ORDER BY t.sk_date ASC) AS is_default_schedule
    FROM 
        timeline AS t 
    LEFT JOIN 
        sale_listings AS s
            USING(sk_house, sk_date)
    LEFT JOIN 
        available_hours_week AS ah
            USING(sk_house, sk_date)
    LEFT JOIN 
        dw_sale.fact_listings AS f
            USING(sk_house)
    LEFT JOIN 
        dw_sale.dim_listing AS l
            USING(sk_house)
    LEFT JOIN 
        dw_public.dim_date AS d
            USING(sk_date)
    WHERE 
        1 = 1 
        AND f.sk_house IS NOT NULL
	AND (s.order_status = 1 OR s.order_status IS NULL) 
	AND ((ah.available_started_date IS NULL) OR (ah.available_started_date IS NOT NULL AND ah.order_day_status = 1))
)
SELECT 
    sk_house,
    sk_region,
    status_history,
    date, 
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
    alteration_week,
    is_default_schedule,
    CURRENT_TIMESTAMP AS ts_load
FROM 
    aux
WHERE 
    1 = 1
    AND YEAR(date) >= 2021 
    AND date = week_start
