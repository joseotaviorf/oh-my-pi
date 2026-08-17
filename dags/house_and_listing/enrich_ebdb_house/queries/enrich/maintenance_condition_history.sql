WITH aud AS (
  SELECT
    LAST_VALUE(h.id_house) IGNORE NULLS OVER (
      PARTITION BY h.id_house_maintenance_condition
      ORDER BY h.rev
    ) AS id_house,
    IF(
      h.maintenance_condition IS NOT NULL,
      CAST(h.maintenance_condition AS STRING),
      'NULL'
    ) AS house_condition,
    COALESCE(u.country_code, 'Undefined') AS country_code,
    h.rev_type,
    -- epoch ms → timestamp (replaces DATEADD(MILLISECOND, % 1000, FROM_UNIXTIME(/1000)))
    TIMESTAMP_MILLIS(r.ts_revision) AS ts_change
  FROM
    datalake_ebdb_clean.house_maintenance_condition_aud AS h
  INNER JOIN
    datalake_ebdb_clean.user_revision_entity AS r
      ON h.rev = r.id
  LEFT JOIN
    datalake_ebdb_country.user AS u
      ON u.id_user = r.id_user
),
deduplicating_changes_at_the_same_time AS (
  SELECT
    id_house,
    house_condition,
    country_code,
    TIMESTAMPADD(
      MILLISECOND,
      RANK() OVER (PARTITION BY id_house, ts_change ORDER BY rev_type DESC) - 1,
      ts_change
    ) AS ts_change
  FROM
    aud
),
last_status_by_day AS (
  SELECT
    id_house,
    house_condition,
    country_code,
    dt_condition_started
  FROM (
    SELECT
      id_house,
      house_condition,
      country_code,
      DATE(ts_change) AS dt_condition_started,
      ROW_NUMBER() OVER (
        PARTITION BY id_house, DATE(ts_change)
        ORDER BY ts_change DESC
      ) AS _w
    FROM
      deduplicating_changes_at_the_same_time
  ) AS _t
  WHERE
    _w = 1
),
only_status_changes AS (
  SELECT
    id_house,
    house_condition,
    country_code,
    dt_condition_started
  FROM (
    SELECT
      id_house,
      house_condition,
      country_code,
      dt_condition_started,
      LAG(house_condition) OVER (
        PARTITION BY id_house
        ORDER BY dt_condition_started
      ) AS prev_house_condition
    FROM
      last_status_by_day
  ) AS _t
  WHERE
    house_condition IS DISTINCT FROM prev_house_condition
)
SELECT
  id_house,
  house_condition,
  country_code,
  ROW_NUMBER() OVER (
    PARTITION BY id_house
    ORDER BY dt_condition_started DESC
  ) = 1 AS is_last_condition,
  dt_condition_started,
  DATE_SUB(
    LEAD(dt_condition_started) OVER (
      PARTITION BY id_house
      ORDER BY dt_condition_started ASC
    ),
    1
  ) AS dt_condition_ended
FROM
  only_status_changes
