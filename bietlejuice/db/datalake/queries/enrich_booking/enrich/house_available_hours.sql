WITH all_events AS (
    SELECT
        wsa.id_house,
        ure.id_user,
        wsa.rev,
        wsa.weekday,
        wsa.is_available_between_08_and_09  AS hours_available_08to09,
        wsa.is_available_between_09_and_10  AS hours_available_09to10,
        wsa.is_available_between_10_and_11  AS hours_available_10to11,
        wsa.is_available_between_11_and_12  AS hours_available_11to12,
        wsa.is_available_between_12_and_13  AS hours_available_12to13,
        wsa.is_available_between_13_and_14  AS hours_available_13to14,
        wsa.is_available_between_14_and_15  AS hours_available_14to15,
        wsa.is_available_between_15_and_16  AS hours_available_15to16,
        wsa.is_available_between_16_and_17  AS hours_available_16to17,
        wsa.is_available_between_17_and_18  AS hours_available_17to18,
        wsa.is_available_between_18_and_19  AS hours_available_18to19,
        wsa.is_available_between_19_and_20  AS hours_available_19to20,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_revision
    FROM 
        datalake_ebdb_clean.house_weekly_schedule_aud wsa
    LEFT JOIN 
        datalake_ebdb_clean.user_revision_entity ure
            ON wsa.rev = ure.id
    -- remove lines WITH registries out of the 7 possible weekdays
    WHERE 
        wsa.weekday BETWEEN 1 AND 7
    UNION -- DISTINCT
    SELECT
        ws.id_house,
        NULL AS id_user,
        0 AS rev, -- priority for auds
        ws.weekday,
        ws.is_available_between_08_and_09  AS hours_available_08to09,
        ws.is_available_between_09_and_10  AS hours_available_09to10,
        ws.is_available_between_10_and_11  AS hours_available_10to11,
        ws.is_available_between_11_and_12  AS hours_available_11to12,
        ws.is_available_between_12_and_13  AS hours_available_12to13,
        ws.is_available_between_13_and_14  AS hours_available_13to14,
        ws.is_available_between_14_and_15  AS hours_available_14to15,
        ws.is_available_between_15_and_16  AS hours_available_15to16,
        ws.is_available_between_16_and_17  AS hours_available_16to17,
        ws.is_available_between_17_and_18  AS hours_available_17to18,
        ws.is_available_between_18_and_19  AS hours_available_18to19,
        ws.is_available_between_19_and_20  AS hours_available_19to20,
        ws.ts_created AS ts_revision
    FROM 
        datalake_ebdb_clean.house_weekly_schedule ws
    WHERE 
        ws.weekday BETWEEN 1 AND 7
),
truncate_daily_events AS (
    SELECT
        id_house,
        CONCAT(id_house, DATE_FORMAT(ts_revision, 'yyyyMMdd'), weekday) AS id_house_date,
        id_user,
        weekday,
        ROW_NUMBER() OVER(PARTITION BY id_house, DATE(ts_revision), weekday ORDER BY rev DESC) AS daily_freshness_order, -- We want to register only one state per day
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
        DATE(ts_revision) AS dt_revision
    FROM
        all_events
),
deduplicated_events AS (
  SELECT
      id_house,
      id_house_date,
      id_user,
      weekday,
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
      dt_revision
  FROM
      truncate_daily_events
  WHERE
      daily_freshness_order = 1
),
-- if the house doesn't appear in house_weekly_schedule THEN it has the default schedule
-- 8h-19h FROM Monday to Friday and 8h-17h in Saturday
houses_without_schedule AS (
    SELECT
        h.id AS id_house,
        DATE(h.dt_creation) AS dt_revision
    FROM 
        datalake_ebdb_clean.house AS h
    LEFT JOIN 
        deduplicated_events AS de
            ON h.id = de.id_house
    WHERE
        de.id_house IS NULL
),
all_schedules AS (
-- Could be in a different table, but
-- it doesn't seem to be valuable outside this scope.
    SELECT
        id_house,
        CONCAT(id_house, DATE_FORMAT(dt_revision, 'yyyyMMdd'), weekday) AS id_house_date,
        NULL AS id_user,
        EXPLODE(SEQUENCE(1,7)) AS weekday,
        IF(weekday <> 7,true, false) AS hours_available_08to09,
        IF(weekday <> 7,true, false) AS hours_available_09to10,
        IF(weekday <> 7,true, false) AS hours_available_10to11,
        IF(weekday <> 7,true, false) AS hours_available_11to12,
        IF(weekday <> 7,true, false) AS hours_available_12to13,
        IF(weekday <> 7,true, false) AS hours_available_13to14,
        IF(weekday <> 7,true, false) AS hours_available_14to15,
        IF(weekday <> 7,true, false) AS hours_available_15to16,
        IF(weekday <> 7,true, false) AS hours_available_16to17,
        IF(weekday NOT IN (6,7),true, false) AS hours_available_17to18,
        IF(weekday NOT IN (6,7),true, false) AS hours_available_18to19,
        IF(weekday NOT IN (6,7),true, false) AS hours_available_19to20,
        dt_revision
	FROM 
        houses_without_schedule
    UNION
    SELECT
        id_house,
        id_house_date,
        id_user,
        weekday,
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
        dt_revision
    FROM
        deduplicated_events
),
house_available_hours AS (
    SELECT
        id_house,
        id_house_date,
        id_user,
        weekday AS day_of_week,
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
        dt_revision AS dt_available_started,
        LEAD(dt_revision) OVER(PARTITION BY id_house, weekday ORDER BY dt_revision) AS dt_available_ended
    FROM 
        all_schedules
)
SELECT
    id_house,
    id_house_date,
    id_user,
    day_of_week,
    CASE 
        WHEN id_house IS NOT NULL THEN AGGREGATE(ARRAY(hours_available_08to09,
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
                                                       hours_available_19to20), 0, (acc,x) -> acc + IF(x = TRUE, 1, 0))
    END AS day_hours_available,
    hours_available_08to09 AS has_hours_available_08to09,
    hours_available_09to10 AS has_hours_available_09to10,
    hours_available_10to11 AS has_hours_available_10to11,
    hours_available_11to12 AS has_hours_available_11to12,
    hours_available_12to13 AS has_hours_available_12to13,
    hours_available_13to14 AS has_hours_available_13to14,
    hours_available_14to15 AS has_hours_available_14to15,
    hours_available_15to16 AS has_hours_available_15to16,
    hours_available_16to17 AS has_hours_available_16to17,
    hours_available_17to18 AS has_hours_available_17to18,
    hours_available_18to19 AS has_hours_available_18to19,
    hours_available_19to20 AS has_hours_available_19to20,
    dt_available_started,
    dt_available_ended
FROM 
    house_available_hours
WHERE
    dt_available_started IS NOT NULL