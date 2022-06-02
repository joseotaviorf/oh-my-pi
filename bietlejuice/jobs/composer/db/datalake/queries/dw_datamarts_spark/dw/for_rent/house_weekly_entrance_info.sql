WITH date_series AS (
  SELECT DISTINCT
    DATE(week_start) AS week_start,
    DATE(week_end) AS week_end
  FROM 
    dw_public.dim_date AS dd
  WHERE 
    DATE(date) >= DATE_ADD(CURRENT_DATE(), -180)
    AND DATE(week_start) < DATE_TRUNC('WEEK', CURRENT_DATE())
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
      id_type,
      rev,
      FROM_UNIXTIME(ure.ts_revision/1000) AS date,
      DATE_ADD(CAST(DATE_TRUNC('WEEK', FROM_UNIXTIME(ure.ts_revision/1000)) AS date), 6) AS week_end
    FROM 
      datalake_ebdb_clean.access_type_aud AS aud
    LEFT JOIN 
      datalake_ebdb_clean.user_revision_entity AS ure
        ON ure.id = aud.rev
    WHERE 
      aud.mod_type = true
  ),
  key_type_ordered AS (
    select
      id_house,
      id_type,
      kt.name AS key_type_history,
      week_end AS week_end_key_type_start,
      COALESCE(LEAD(week_end) OVER (PARTITION BY id_house ORDER BY date), DATE_ADD(DATE_TRUNC('week', CURRENT_DATE()), 6)) AS week_end_key_type_end,
      ROW_NUMBER() OVER (PARTITION BY id_house, week_end ORDER BY date DESC) AS order_key_type
    FROM 
      key_type_aud
    LEFT JOIN 
      datalake_ebdb_clean.key_type AS kt
        ON kt.id = key_type_aud.id_type
  )
  SELECT
    id_house,
    key_type_history,
    dd.week_start,
    dd.week_end,
    week_end_key_type_start,
    week_end_key_type_end
  FROM key_type_ordered
  JOIN date_series AS dd
    ON dd.week_end >= week_end_key_type_start 
    AND dd.week_end < week_end_key_type_end
  WHERE order_key_type = 1
 ),
key_location_base AS (
  WITH key_location_aud AS (
    SELECT
      id_house,
      id_authorization,
      rev,
      FROM_UNIXTIME(ure.ts_revision/1000) AS date,
      DATE_ADD(CAST(DATE_TRUNC('WEEK', FROM_UNIXTIME(ure.ts_revision/1000)) AS DATE), 6) AS week_end
    FROM datalake_ebdb_clean.access_type_aud AS aud
    LEFT JOIN datalake_ebdb_clean.user_revision_entity AS ure
      ON ure.id = aud.rev
    WHERE aud.mod_authorization = true
  ),
  key_location_ordered AS (
    SELECT
      id_house,
      id_authorization,
      at.name AS key_location_history,
      week_end AS week_end_key_location_start,
      COALESCE(LEAD(week_end) OVER (PARTITION BY id_house ORDER BY date), DATE_ADD(DATE_TRUNC('week', current_date), 6)) AS week_end_key_location_end,
      ROW_NUMBER() OVER (PARTITION BY id_house, week_end ORDER BY date DESC) AS order_key_location
    FROM 
      key_location_aud
    LEFT JOIN 
      datalake_ebdb_clean.access_authorization_type AS at
        ON at.id = key_location_aud.id_authorization
  )
  SELECT
    id_house,
    key_location_history,
    dd.week_start,
    dd.week_end,
    week_end_key_location_start,
    week_end_key_location_end
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
      id_occupant,
      rev,
      FROM_UNIXTIME(ure.ts_revision/1000) AS date,
      DATE_ADD(CAST(DATE_TRUNC('WEEK', FROM_UNIXTIME(ure.ts_revision/1000)) AS date), 6) AS week_end
    FROM 
      datalake_ebdb_clean.access_type_aud AS aud
    LEFT JOIN 
      datalake_ebdb_clean.user_revision_entity AS ure
        ON ure.id = aud.rev
    WHERE 
      aud.mod_occupant = true
  ),
  who_is_living_ordered AS (
    SELECT
      id_house,
      id_occupant,
      ot.name AS who_is_living_history,
      week_end AS week_end_who_is_living_start,
      COALESCE(LEAD(week_end) OVER (PARTITION BY id_house ORDER BY date), DATE_ADD(DATE_TRUNC('WEEK', current_date), 6)) AS week_end_who_is_living_end,
      ROW_NUMBER() OVER (PARTITION BY id_house, week_end ORDER BY date DESC) AS order_who_is_living
    FROM  
      who_is_living_aud
    LEFT JOIN 
      datalake_ebdb_clean.occupant_type AS ot
        ON ot.id = who_is_living_aud.id_occupant
  )
  SELECT
    id_house,
    who_is_living_history,
    dd.week_start,
    dd.week_end,
    week_end_who_is_living_start,
    week_end_who_is_living_end
  FROM 
    who_is_living_ordered
  JOIN 
    date_series AS dd
      ON dd.week_end >= week_end_who_is_living_start 
      AND dd.week_end < week_end_who_is_living_end
  WHERE 
    order_who_is_living = 1
),
house_weekly_entrance AS (
  SELECT
    STRING(hds.id_house) AS id_house,
    STRING(klb.key_location_history) AS key_location_history,
    STRING(ktb.key_type_history) AS key_type_history,
    STRING(wlb.who_is_living_history) AS who_is_living_history,
    STRING(hds.week_start) AS week_start,
    STRING(hds.week_end) AS week_end,
    STRING(NOW()) AS ts_load
  FROM 
    house_date_series AS hds
  LEFT JOIN 
    key_location_base AS klb
      ON klb.id_house = hds.id_house 
      AND hds.week_end = klb.week_end
  LEFT JOIN 
    key_type_base AS ktb
      ON ktb.id_house = hds.id_house
      AND ktb.week_end = hds.week_end
  LEFT JOIN 
    who_is_living_base AS wlb
      ON wlb.id_house = hds.id_house 
      AND hds.week_end = wlb.week_end
  WHERE 
    klb.id_house IS NOT NULL
  ORDER BY 3,2
)
SELECT *
FROM house_weekly_entrance