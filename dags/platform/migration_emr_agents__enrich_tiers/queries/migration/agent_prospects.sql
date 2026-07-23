WITH prospect_daily_results AS (
  SELECT
    id_prospect,
    id_booking,
    id_agent,
    event_name,
    business_context,
    referral_type,
    ts_event,
    dt_event,
    year,
    month,
    day
  FROM (
    SELECT
      pdr.id_prospect,
      pdr.id_booking,
      pdr.id_agent,
      pdr.event_name,
      pdr.business_context,
      pdr.referral_type,
      pdr.ts_event,
      CAST(pdr.ts_event AS DATE) AS dt_event,
      pdr.year,
      pdr.month,
      pdr.day,
      ROW_NUMBER() OVER (PARTITION BY COALESCE(pdr.id_rent_flow, pdr.id_sale_flow), pdr.event_type, pdr.business_context ORDER BY pdr.ts_event ASC) AS _w,
      pdr.event_type,
      pdr.id_rent_flow,
      pdr.id_sale_flow
    FROM datalake_demand_flows.prospect_daily_results AS pdr
  ) AS _t
  WHERE
    1 = _w
)
SELECT
  pdr.id_agent,
  u.id AS id_user,
  u.uuid_person,
  pdr.id_prospect,
  UPPER(pdr.business_context) AS business_context,
  pdr.event_name,
  pdr.ts_event,
  pdr.year,
  pdr.month,
  pdr.day
FROM prospect_daily_results AS pdr
JOIN datalake_ebdb_user.user AS u
  ON u.id_agent = pdr.id_agent
WHERE
  MAKE_DATE(pdr.year, pdr.month, pdr.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  AND NOT pdr.id_agent IS NULL
  AND pdr.event_name IN ('USER FIRST ACTIVATION', 'USER RECOVERY', 'USER RECOVERY IN OTHER CITY GROUP')
  AND pdr.referral_type <> 'Rede'