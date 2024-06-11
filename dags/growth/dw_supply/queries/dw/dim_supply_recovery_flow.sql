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
  *,
  CONCAT_WS(
    '#',
    tp_reprocessing, 
    tp_reprocessing_entity, 
    nm_mailing_table
  ) AS bk_recovery
FROM reprocessing_flow