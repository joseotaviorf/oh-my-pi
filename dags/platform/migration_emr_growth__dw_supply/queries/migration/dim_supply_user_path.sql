WITH base AS (
  SELECT DISTINCT
    1 AS id_level,
    aux_origin_table AS ds_level, 
    COALESCE(application, 'not_mapped') AS tp_origin, 
    COALESCE(platform, 'not_mapped') AS tp_platform,
    'n/a' AS nm_content_page
  FROM datalake_supply_flows.supply_events_tracking
  WHERE aux_origin_table = 'acquisition'
  UNION 
  SELECT DISTINCT
    2 AS id_level,
    aux_origin_table AS ds_level, 
    application AS tp_origin, 
    'n/a' AS tp_platform,
    'n/a' AS nm_content_page
  FROM datalake_supply_flows.supply_events_tracking
  WHERE aux_origin_table = 'conversion'
)

SELECT
  base.id_level,
  base.ds_level,
  base.tp_origin,
  base.tp_platform,
  base.nm_content_page,
  CONCAT_WS(
    '#',
    base.tp_origin,
    base.tp_platform,
    base.nm_content_page
  ) AS bk_user_path,
  NOW() AS ts_updated
FROM
  base