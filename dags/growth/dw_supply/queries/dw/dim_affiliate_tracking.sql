WITH dedup AS (
  SELECT 
    id_referred_by, 
    ts_event_adjusted,
    MODE(affiliate_type) AS affiliate_type
  FROM datalake_supply_flows.supply_events_tracking
  WHERE supply_source = '1P'
      AND affiliate_type IS NOT NULL
      AND id_referred_by IS NOT NULL
      AND id_referred_by != -1
      AND business_event = 'acquisition_tof2l'
  GROUP BY 1, 2
),
base AS (
  SELECT 
    id_referred_by AS sk_user_affiliate, 
    affiliate_type, 
    ts_event_adjusted,
    LAG(affiliate_type) OVER (PARTITION BY id_referred_by ORDER BY ts_event_adjusted, affiliate_type ASC) AS last_affiliate_type,
    COALESCE(affiliate_type != last_affiliate_type, FALSE) AS mod_affiliate_type
  FROM dedup
),
calculated AS (
    SELECT 
    sk_user_affiliate, 
    affiliate_type, 
    last_affiliate_type, 
    ts_event_adjusted AS ts_started, 
    -- LEAD(timestampadd(SECOND, -1, ts_event_adjusted)) OVER (PARTITION BY sk_user_affiliate ORDER BY ts_event_adjusted) AS ts_ended
    LEAD(ts_event_adjusted) OVER (PARTITION BY sk_user_affiliate ORDER BY ts_event_adjusted) AS ts_ended
  FROM base
  WHERE mod_affiliate_type IS TRUE
    OR last_affiliate_type IS NULL
)

SELECT
  sk_user_affiliate, 
  affiliate_type, 
  last_affiliate_type, 
  ROW_NUMBER() OVER (PARTITION BY sk_user_affiliate ORDER BY ts_started) AS version,
  date_format(ts_started, 'yyyyMMdd') AS sk_start_date,
  date_format(ts_ended, 'yyyyMMdd') AS sk_end_date,
  ts_started,
  ts_ended,
  NOW() AS ts_updated
FROM calculated