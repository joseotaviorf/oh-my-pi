WITH discards AS (
  SELECT
    DISTINCT LOWER(funnel_step) AS funnel_step,
    LOWER(drop_step_reason) AS discard_reason
  FROM
    datalake_supply_flows.supply_events_tracking
  WHERE
    drop_step_reason IS NOT NULL
)
SELECT
  CONCAT_WS('#', ds.funnel_step, ds.discard_reason) AS bk_discard,
  ds.funnel_step AS cd_funnel_step,
  ds.discard_reason AS cd_discard_reason,
  'Not Mapped' AS ds_discard_reason,
  NOW() AS ts_updated
FROM
  discards AS ds