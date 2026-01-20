WITH date_series AS (
  SELECT DISTINCT
    DATE(week_start) AS week_start,
    DATE(week_end) AS week_end
  FROM
    datalake_quintoandar.aux_date AS dd
  WHERE
    DATE(week_start) < DATE_TRUNC('WEEK', CURRENT_DATE())
    AND date >= '2021-01-01'
),
house_date_series AS (
  SELECT DISTINCT
    h.id AS id_house,
    dd.week_start,
    dd.week_end
  FROM
    datalake_ebdb_clean.house AS h
  CROSS JOIN
    date_series AS dd
  WHERE
    h.dt_first_publication IS NOT NULL
),
entry_base AS (
  WITH entry_aud AS (
    SELECT
      id_house,
      key_type AS key_type_history,
      key_location AS key_location_history,
      occupant_type AS who_is_living_history,
      ts_entrance_started AS ts_event,
      DATE_ADD(DATE_TRUNC('WEEK', ts_entrance_started), 6) AS week_end
    FROM
      datalake_ebdb_listing.house_entrance_history
    WHERE
      mod_type
      OR mod_occupant
      OR mod_authorization
  ),
  entry_ordered AS (
    SELECT
      id_house,
      key_type_history,
      key_location_history,
      who_is_living_history,
      week_end AS week_end_key_type_start,
      COALESCE(LEAD(week_end) OVER (PARTITION BY id_house ORDER BY ts_event), DATE_ADD(DATE_TRUNC('week', CURRENT_DATE()), 6)) AS week_end_key_type_end
    FROM
      entry_aud
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id_house, week_end ORDER BY ts_event DESC) = 1
  )
  SELECT
    id_house,
    key_type_history,
    key_location_history,
    who_is_living_history,
    dd.week_start,
    dd.week_end
  FROM
    entry_ordered
  JOIN
    date_series AS dd
      ON dd.week_end >= week_end_key_type_start
      AND dd.week_end < week_end_key_type_end
 ),
house_entrance_base AS (
  WITH house_entrance_aud AS (
    SELECT
      id_house,
      doorman_type,
      ure.ts_revision AS ts_event,
      DATE_ADD(CAST(DATE_TRUNC('WEEK', ure.ts_revision) AS DATE), 6) AS week_end
    FROM
      datalake_ebdb_clean.house_aud AS aud
    JOIN
      datalake_ebdb_user.user_revision_entity AS ure
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
  entry.key_location_history,
  entry.key_type_history,
  entry.who_is_living_history,
  hds.week_start AS dt_week_started,
  hds.week_end AS dt_week_ended
FROM
  house_date_series AS hds
JOIN
  entry_base AS entry
    ON hds.id_house = entry.id_house
    AND hds.week_end = entry.week_end
JOIN
  house_entrance_base AS heb
    ON hds.id_house = heb.id_house
    AND hds.week_end = heb.week_end
