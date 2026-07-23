WITH reprocessing_flow AS (
  SELECT DISTINCT 
    1 AS id_level,
    'reprocessing_flow' AS ds_level,
    reprocessed AS tp_reprocessing, 
    reprocessing_entity_type AS tp_reprocessing_entity, 
    reprocessing_table_name AS nm_mailing_table,
    NOW() AS ts_updated
  FROM datalake_supply_flows.supply_events_tracking
  WHERE reprocessed IS NOT NULL
)

SELECT
  reprocessing_flow.id_level,
  reprocessing_flow.ds_level,
  reprocessing_flow.tp_reprocessing,
  reprocessing_flow.tp_reprocessing_entity,
  reprocessing_flow.nm_mailing_table,
  reprocessing_flow.ts_updated,
  CONCAT_WS(
    '#',
    reprocessing_flow.tp_reprocessing,
    reprocessing_flow.tp_reprocessing_entity,
    reprocessing_flow.nm_mailing_table
  ) AS bk_recovery
FROM
  reprocessing_flow