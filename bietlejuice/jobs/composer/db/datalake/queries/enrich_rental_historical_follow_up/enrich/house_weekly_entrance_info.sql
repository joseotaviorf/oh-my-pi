WITH date_series AS (
  SELECT DISTINCT
    DATE(week_start) AS week_start,
    DATE(week_end) AS week_end
  FROM 
    datalake_quintoandar.aux_date AS dd
  WHERE 
    DATE(week_start) < DATE_TRUNC('WEEK', CURRENT_DATE())
    AND "date" != ''
),
house_date_series AS (
  SELECT DISTINCT
    h.id AS id_house,
    dd.week_start,
    dd.week_end
  FROM 
    datalake_ebdb_clean.house AS h
  JOIN 
    datalake_ebdb_clean.access_type AS at
      ON at.id_house = h.id
  CROSS JOIN 
    date_series AS dd
  WHERE 
    h.dt_first_publication IS NOT NULL
),
key_type_base AS (
  WITH key_type_aud AS (
    SELECT
      id_house,
      kt.name AS key_type_history,
      FROM_UNIXTIME(ure.ts_revision/1000) AS ts_event,
      DATE_ADD(CAST(DATE_TRUNC('WEEK', FROM_UNIXTIME(ure.ts_revision/1000)) AS DATE), 6) AS week_end
    FROM 
      datalake_ebdb_clean.access_type_aud AS aud
    LEFT JOIN 
      datalake_ebdb_clean.user_revision_entity AS ure
        ON aud.rev = ure.id
    LEFT JOIN 
      datalake_ebdb_clean.key_type AS kt
        ON aud.id_type = kt.id
    WHERE 
      aud.mod_type = true
  ),
  key_type_ordered AS (
    SELECT
      id_house,
      key_type_history,
      week_end AS week_end_key_type_start,
      COALESCE(LEAD(week_end) OVER (PARTITION BY id_house ORDER BY ts_event), DATE_ADD(DATE_TRUNC('week', CURRENT_DATE()), 6)) AS week_end_key_type_end,
      ROW_NUMBER() OVER (PARTITION BY id_house, week_end ORDER BY ts_event DESC) AS order_key_type
    FROM 
      key_type_aud
  )
  SELECT
    id_house,
    key_type_history,
    dd.week_start,
    dd.week_end
  FROM 
    key_type_ordered
  JOIN 
    date_series AS dd
      ON dd.week_end >= week_end_key_type_start 
      AND dd.week_end < week_end_key_type_end
  WHERE 
    order_key_type = 1
 ),
key_location_base AS (
  WITH key_location_aud AS (
    SELECT
      id_house,
      at.name AS key_location_history,
      FROM_UNIXTIME(ure.ts_revision/1000) AS ts_event,
      DATE_ADD(CAST(DATE_TRUNC('WEEK', FROM_UNIXTIME(ure.ts_revision/1000)) AS DATE), 6) AS week_end
    FROM 
      datalake_ebdb_clean.access_type_aud AS aud
    LEFT JOIN 
      datalake_ebdb_clean.user_revision_entity AS ure
        ON aud.rev = ure.id
    LEFT JOIN 
      datalake_ebdb_clean.access_authorization_type AS at
        ON aud.id_authorization = at.id
    WHERE 
      aud.mod_authorization = true
  ),
  key_location_ordered AS (
    SELECT
      id_house,
      key_location_history,
      week_end AS week_end_key_location_start,
      COALESCE(LEAD(week_end) OVER (PARTITION BY id_house ORDER BY ts_event), DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE()), 6)) AS week_end_key_location_end,
      ROW_NUMBER() OVER (PARTITION BY id_house, week_end ORDER BY ts_event DESC) AS order_key_location
    FROM 
      key_location_aud
  )
  SELECT
    id_house,
    key_location_history,
    dd.week_start,
    dd.week_end
  FROM 
    key_location_ordered
  JOIN 
    date_series AS dd
      ON dd.week_end >= week_end_key_location_start 
      AND dd.week_end < week_end_key_location_end
  WHERE 
    order_key_location = 1
),
who_is_living_base AS (
  WITH who_is_living_aud AS (
    SELECT
      id_house,
      ot.name AS who_is_living_history,
      FROM_UNIXTIME(ure.ts_revision/1000) AS ts_event,
      DATE_ADD(CAST(DATE_TRUNC('WEEK', FROM_UNIXTIME(ure.ts_revision/1000)) AS DATE), 6) AS week_end
    FROM 
      datalake_ebdb_clean.access_type_aud AS aud
    LEFT JOIN 
      datalake_ebdb_clean.user_revision_entity AS ure
        ON aud.rev = ure.id
    LEFT JOIN 
      datalake_ebdb_clean.occupant_type AS ot
        ON aud.id_occupant = ot.id
    WHERE
      aud.mod_occupant = true
  ),
  who_is_living_ordered AS (
    SELECT
      id_house,
      who_is_living_history,
      week_end AS week_end_who_is_living_start,
      COALESCE(LEAD(week_end) OVER (PARTITION BY id_house ORDER BY ts_event), DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE()), 6)) AS week_end_who_is_living_end,
      ROW_NUMBER() OVER (PARTITION BY id_house, week_end ORDER BY ts_event DESC) AS order_who_is_living
    FROM 
      who_is_living_aud
  )
  SELECT
    id_house,
    who_is_living_history,
    dd.week_start,
    dd.week_end
  FROM 
    who_is_living_ordered
  JOIN 
    date_series AS dd
      ON dd.week_end >= week_end_who_is_living_start 
      AND dd.week_end < week_end_who_is_living_end
  WHERE 
    order_who_is_living = 1
),
house_entrance_base AS (
  WITH house_entrance_aud AS (
    SELECT
      id_house,
      doorman_type,
      FROM_UNIXTIME(ure.ts_revision/1000) AS ts_event,
      DATE_ADD(CAST(DATE_TRUNC('WEEK', FROM_UNIXTIME(ure.ts_revision/1000)) AS DATE), 6) AS week_end
    FROM 
      datalake_ebdb_clean.house_aud AS aud
    LEFT JOIN 
      datalake_ebdb_clean.user_revision_entity AS ure
        ON ure.id = aud.rev
  ),
  house_entrance_ordered AS (
    SELECT
      id_house,
      doorman_type,
      week_end AS week_end_house_entrance_start,
      COALESCE(LEAD(week_end) OVER (PARTITION BY id_house ORDER BY ts_event), DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE()), 6)) AS week_end_house_entrance_end
    FROM 
      house_entrance_aud
  )
  SELECT
    id_house,
    doorman_type AS house_entrance_history,
    dd.week_start,
    dd.week_end
  FROM 
    house_entrance_ordered
  JOIN
    date_series AS dd
      ON dd.week_end >= week_end_house_entrance_start 
      AND dd.week_end < week_end_house_entrance_end
)
SELECT
  hds.id_house,
  heb.house_entrance_history,
  klb.key_location_history,
  ktb.key_type_history,
  wlb.who_is_living_history,
  hds.week_start AS dt_week_started,
  hds.week_end AS dt_week_ended
FROM 
  house_date_series AS hds
LEFT JOIN 
  key_location_base AS klb
    ON hds.id_house = klb.id_house
    AND hds.week_end = klb.week_end
LEFT JOIN 
  key_type_base AS ktb
    ON hds.id_house = ktb.id_house
    AND hds.week_end = ktb.week_end
LEFT JOIN 
  who_is_living_base AS wlb
    ON hds.id_house = wlb.id_house
    AND hds.week_end = wlb.week_end
LEFT JOIN house_entrance_base AS heb
    ON hds.id_house = heb.id_house
    AND hds.week_end = heb.week_end
WHERE 
  klb.id_house IS NOT NULL