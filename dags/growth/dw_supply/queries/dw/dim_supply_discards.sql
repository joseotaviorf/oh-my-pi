WITH discards AS (
  SELECT
    DISTINCT LOWER(funnel_step) AS funnel_step,
    LOWER(drop_step_reason) AS discard_reason
  FROM
    datalake_supply_flows.supply_events_tracking
  WHERE
    drop_step_reason IS NOT NULL
),
stg_supply_discards AS (
  SELECT
    CONCAT_WS('#', ds.funnel_step, ds.discard_reason) AS bk_discard,
    ds.funnel_step AS cd_funnel_step,
    ds.discard_reason AS cd_discard_reason,
    'Not Mapped' AS ds_discard_reason,
    NOW() AS ts_updated
  FROM
    discards AS ds
  GROUP BY ALL
)

SELECT 
  bk_discard,
  cd_funnel_step,
  cd_discard_reason,
  COALESCE(dd.ds_discard_reason, spd.ds_discard_reason) AS ds_discard_reason,
  ts_updated
FROM 
  stg_supply_discards AS spd
LEFT JOIN 
  datalake_supply_flows.discards_description AS dd
    USING(bk_discard)