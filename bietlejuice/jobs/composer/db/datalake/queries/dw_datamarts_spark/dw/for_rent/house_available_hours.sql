WITH schedule_aud AS (
-- Filling the missing rows in AUD WITH the information FROM the main HorarioSemanalImovel table
    SELECT
        COALESCE(saud.id_house, ws.id_house) AS id_house,
        ws.id,
        FROM_UNIXTIME(ure.ts_revision/1000) AS date_time,
        saud.rev,
        COALESCE(saud.weekday, ws.weekday) AS weekday,
        COALESCE(saud.is_available_between_08_and_09,ws.is_available_between_08_and_09)  AS hours_available_08to09,
        COALESCE(saud.is_available_between_09_and_10,ws.is_available_between_09_and_10)  AS hours_available_09to10,
        COALESCE(saud.is_available_between_10_and_11,ws.is_available_between_10_and_11)  AS hours_available_10to11,
        COALESCE(saud.is_available_between_11_and_12,ws.is_available_between_11_and_12)  AS hours_available_11to12,
        COALESCE(saud.is_available_between_12_and_13,ws.is_available_between_12_and_13)  AS hours_available_12to13,
        COALESCE(saud.is_available_between_13_and_14,ws.is_available_between_13_and_14)  AS hours_available_13to14,
        COALESCE(saud.is_available_between_14_and_15,ws.is_available_between_14_and_15)  AS hours_available_14to15,
        COALESCE(saud.is_available_between_15_and_16,ws.is_available_between_15_and_16)  AS hours_available_15to16,
        COALESCE(saud.is_available_between_16_and_17,ws.is_available_between_16_and_17)  AS hours_available_16to17,
        COALESCE(saud.is_available_between_17_and_18,ws.is_available_between_17_and_18)  AS hours_available_17to18,
        COALESCE(saud.is_available_between_18_and_19,ws.is_available_between_18_and_19)  AS hours_available_18to19,
        COALESCE(saud.is_available_between_19_and_20,ws.is_available_between_19_and_20)  AS hours_available_19to20,
        ws.ts_created,
        ws.ts_updated
	FROM 
        datalake_ebdb_clean.house_weekly_schedule ws
	LEFT JOIN 
        datalake_ebdb_clean.house_weekly_schedule_aud saud
            ON saud.id = ws.id
	LEFT JOIN 
        datalake_ebdb_clean.user_revision_entity ure
            ON saud.rev = ure.id
	-- remove lines WITH registries out of the 7 possible weekdays
	WHERE 
        COALESCE(saud.weekday, ws.weekday) BETWEEN 1 AND 7
),
-- if the house doesn't appear in house_weekly_schedule THEN it has the default schedule
-- 8h-19h FROM Monday to Friday and 8h-17h in Saturday
default_schedule_base AS (
    SELECT
        h.id AS id_house,
        h.dt_creation
    FROM 
        datalake_ebdb_clean.house h
    LEFT JOIN 
        schedule_aud sa
            ON h.id = sa.id_house
    WHERE
        sa.id_house IS NULL
),
house_default_schedule AS (
    SELECT
        id_house,
        dt_creation,
        1 AS weekday,
        true AS hours_available_08to09,
        true AS hours_available_09to10,
        true AS hours_available_10to11,
        true AS hours_available_11to12,
        true AS hours_available_12to13,
        true AS hours_available_13to14,
        true AS hours_available_14to15,
        true AS hours_available_15to16,
        true AS hours_available_16to17,
        true AS hours_available_17to18,
        true AS hours_available_18to19,
        false AS hours_available_19to20
	FROM 
        default_schedule_base
	UNION ALL
    SELECT
        id_house,
        dt_creation,
        2 AS weekday,
        true AS hours_available_08to09,
		true AS hours_available_09to10,
		true AS hours_available_10to11,
		true AS hours_available_11to12,
		true AS hours_available_12to13,
		true AS hours_available_13to14,
		true AS hours_available_14to15,
		true AS hours_available_15to16,
		true AS hours_available_16to17,
		true AS hours_available_17to18,
		true AS hours_available_18to19,
		false AS hours_available_19to20
	FROM 
        default_schedule_base
	UNION ALL
	SELECT
        id_house,
        dt_creation,
        3 AS weekday,
        true AS hours_available_08to09,
		true AS hours_available_09to10,
		true AS hours_available_10to11,
		true AS hours_available_11to12,
		true AS hours_available_12to13,
		true AS hours_available_13to14,
		true AS hours_available_14to15,
		true AS hours_available_15to16,
		true AS hours_available_16to17,
		true AS hours_available_17to18,
		true AS hours_available_18to19,
		false AS hours_available_19to20
	FROM 
        default_schedule_base
	UNION ALL
	SELECT
        id_house,
        dt_creation,
        4 AS weekday,
        true AS hours_available_08to09,
		true AS hours_available_09to10,
		true AS hours_available_10to11,
		true AS hours_available_11to12,
		true AS hours_available_12to13,
		true AS hours_available_13to14,
		true AS hours_available_14to15,
		true AS hours_available_15to16,
		true AS hours_available_16to17,
		true AS hours_available_17to18,
		true AS hours_available_18to19,
		false AS hours_available_19to20
	FROM default_schedule_base
	UNION ALL
	SELECT
        id_house,
        dt_creation,
        5 AS weekday,
        true AS hours_available_08to09,
		true AS hours_available_09to10,
		true AS hours_available_10to11,
		true AS hours_available_11to12,
		true AS hours_available_12to13,
		true AS hours_available_13to14,
		true AS hours_available_14to15,
		true AS hours_available_15to16,
		true AS hours_available_16to17,
		true AS hours_available_17to18,
		true AS hours_available_18to19,
		false AS hours_available_19to20
	FROM 
        default_schedule_base
	UNION ALL
	SELECT
        id_house,
        dt_creation,
        6 AS weekday,
        true AS hours_available_08to09,
		true AS hours_available_09to10,
		true AS hours_available_10to11,
		true AS hours_available_11to12,
		true AS hours_available_12to13,
		true AS hours_available_13to14,
		true AS hours_available_14to15,
		true AS hours_available_15to16,
		true AS hours_available_16to17,
		false AS hours_available_17to18,
		false AS hours_available_18to19,
		false AS hours_available_19to20
	FROM 
        default_schedule_base
	UNION ALL
	SELECT
        id_house,
        dt_creation,
        7 AS weekday,
        false AS hours_available_08to09,
		false AS hours_available_09to10,
		false AS hours_available_10to11,
		false AS hours_available_11to12,
		false AS hours_available_12to13,
		false AS hours_available_13to14,
		false AS hours_available_14to15,
		false AS hours_available_15to16,
		false AS hours_available_16to17,
		false AS hours_available_17to18,
		false AS hours_available_18to19,
		false AS hours_available_19to20
	FROM 
        default_schedule_base
)
, house_available_hours AS (
    SELECT
        COALESCE(sa.id_house, hd.id_house) AS id_house,
        COALESCE(sa.date_time, sa.ts_created, hd.dt_creation) AS available_started_date,
        lead(sa.date_time) OVER(PARTITION BY sa.id_house, sa.weekday ORDER BY sa.rev) AS available_ended_date,
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
        schedule_aud sa
    FULL OUTER JOIN 
        house_default_schedule hd
            ON hd.id_house = sa.id_house
            AND hd.weekday = sa.weekday
)
SELECT
	id_house,
	COALESCE(cast(DATE_FORMAT(available_started_date, 'yyyyMMdd') AS BIGINT),-1) AS sk_available_started_date,
	COALESCE(cast(DATE_FORMAT(available_ended_date, 'yyyyMMdd') AS BIGINT),-1) AS sk_available_ended_date,
	available_started_date,
	available_ended_date,
	day_of_week,
	hours_available_08to09,
	hours_available_09to10,
	hours_available_10to11,
	hours_available_11to12,
	hours_available_12to13,
	hours_available_13to14,
	hours_available_14to15,
	hours_available_15to16,
	hours_available_16to17,
	hours_available_17to18,
	hours_available_18to19,
	hours_available_19to20,
	CASE 
        WHEN id_house IS NOT NULL THEN
            CASE WHEN hours_available_08to09 = true THEN 1 else 0 END + CASE WHEN hours_available_09to10 = true THEN 1 else 0 END + CASE WHEN hours_available_10to11 = true THEN 1 else 0 END +
            CASE WHEN hours_available_11to12 = true THEN 1 else 0 END + CASE WHEN hours_available_12to13 = true THEN 1 else 0 END + CASE WHEN hours_available_13to14 = true THEN 1 else 0 END +
            CASE WHEN hours_available_14to15 = true THEN 1 else 0 END + CASE WHEN hours_available_15to16 = true THEN 1 else 0 END + CASE WHEN hours_available_16to17 = true THEN 1 else 0 END +
            CASE WHEN hours_available_17to18 = true THEN 1 else 0 END + CASE WHEN hours_available_18to19 =  true THEN 1 else 0 END + CASE WHEN hours_available_19to20 = true THEN 1 else 0 END
    END AS day_hours_available,
    NOW() AS ts_load
FROM 
    house_available_hours