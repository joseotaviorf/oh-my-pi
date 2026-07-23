WITH
consumption_bill_aud as (
  SELECT
    aud.id_house,
    aud.type,
    aud.is_condo_included,
    DATE(ure.ts_revision) AS dt_revision
  FROM
    datalake_ebdb_clean.consumption_bill_aud AS aud
  JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON aud.rev = ure.id
  QUALIFY
    MAX(ure.ts_revision) OVER (PARTITION BY aud.id_house, aud.type, DATE(ure.ts_revision)) = ure.ts_revision
),

combined_status AS (
  SELECT
    id_house,
    MAX(IF(type = 'Agua', is_condo_included, NULL)) AS is_water_included_in_condo,
    MAX(IF(type = 'Luz', is_condo_included, NULL)) AS is_power_included_in_condo,
    MAX(IF(type = 'Gas', is_condo_included, NULL)) AS is_gas_included_in_condo,
    dt_revision
  FROM
    consumption_bill_aud
  GROUP BY
    ALL
),

previous_status AS (
  SELECT
    id_house,
    is_water_included_in_condo,
    LAG(is_water_included_in_condo) OVER (PARTITION BY id_house ORDER BY dt_revision) AS previous_is_water_included_in_condo,
    is_power_included_in_condo,
    LAG(is_power_included_in_condo) OVER (PARTITION BY id_house ORDER BY dt_revision) AS previous_is_power_included_in_condo,
    is_gas_included_in_condo,
    LAG(is_gas_included_in_condo) OVER (PARTITION BY id_house ORDER BY dt_revision) AS previous_is_gas_included_in_condo,
    dt_revision
  FROM
    combined_status
  QUALIFY
    is_water_included_in_condo != previous_is_water_included_in_condo
    OR is_power_included_in_condo != previous_is_power_included_in_condo
    OR is_gas_included_in_condo != previous_is_gas_included_in_condo
    OR previous_is_water_included_in_condo IS NULL
    OR previous_is_power_included_in_condo IS NULL
    OR previous_is_gas_included_in_condo IS NULL
)

SELECT
  id_house,
  IFNULL(is_water_included_in_condo, LAG(is_water_included_in_condo) OVER (PARTITION BY id_house ORDER BY dt_revision)) AS is_water_included_in_condo,
  IFNULL(is_power_included_in_condo, LAG(is_power_included_in_condo) OVER (PARTITION BY id_house ORDER BY dt_revision)) AS is_power_included_in_condo,
  IFNULL(is_gas_included_in_condo, LAG(is_gas_included_in_condo) OVER (PARTITION BY id_house ORDER BY dt_revision)) AS is_gas_included_in_condo,
  dt_revision AS dt_status_started,
  LEAD(dt_revision) OVER (PARTITION BY id_house ORDER BY dt_revision) AS dt_status_ended
FROM
  previous_status
