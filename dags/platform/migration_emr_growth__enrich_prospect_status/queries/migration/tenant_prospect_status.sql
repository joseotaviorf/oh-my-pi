WITH rent_flows AS (
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    id_event_type,
    city_group,
    event_name,
    is_rent_flow_event,
    ts_event
  FROM (
    SELECT
      dpce.id_demand_prospect_conversion_event,
      dpce.id_prospect AS id_tenant_prospect,
      dpce.id_event_type,
      r.city_group,
      dpce.event_name,
      TRUE AS is_rent_flow_event,
      dpce.ts_event,
      ROW_NUMBER() OVER (PARTITION BY id_prospect, id_house ORDER BY ts_event ASC) AS _w,
      id_prospect,
      id_house
    FROM datalake_demand_flows.conversion_events AS dpce
    LEFT JOIN datalake_region.region AS r
      ON dpce.id_region = r.id
    WHERE
      business_context = 'rent'
  ) AS _t
  WHERE
    _w = 1 /* Get only the first user's rent flow */
), tps_contracts AS (
  SELECT DISTINCT
    rf.id_client AS id_tenant_prospect,
    r.city_group,
    FALSE AS is_rent_flow_event,
    ct.ts_signed AS ts_contract_signed,
    DATE_ADD(CAST(ct.dt_termination AS TIMESTAMP), 86399) AS ts_contract_terminated,
    CAST(NULL AS INT) AS cs_order
  FROM datalake_ebdb_contract.contract AS ct
  JOIN datalake_ebdb_rent_flow.rent_flow AS rf
    ON rf.id_contract = ct.id
  LEFT JOIN datalake_ebdb_clean.house AS h
    ON h.id = ct.id_house
  LEFT JOIN datalake_region.region AS r
    ON h.id_region = r.id
), contracts_person AS (
  SELECT
    ctp.id_user_contract_person AS id_tenant_prospect,
    r.city_group,
    FALSE AS is_rent_flow_event,
    ct.ts_signed AS ts_contract_signed,
    DATE_ADD(CAST(ct.dt_termination AS TIMESTAMP), 86399) AS ts_contract_terminated,
    ROW_NUMBER() OVER (PARTITION BY ctp.id_user_contract_person, ctp.id_contract, ct.ts_signed ORDER BY ctp.contract_role DESC) AS cs_order
  FROM datalake_ebdb_contract.contract AS ct
  LEFT JOIN datalake_ebdb_contract.contract_person AS ctp
    ON ct.id = ctp.id_contract
  LEFT JOIN datalake_ebdb_clean.house AS h
    ON h.id = ct.id_house
  LEFT JOIN datalake_region.region AS r
    ON h.id_region = r.id
  FULL OUTER JOIN tps_contracts AS tc /* Anti Join with tps_contracts to get only aditional users */
    ON ctp.id_user_contract_person = tc.id_tenant_prospect
    AND tc.ts_contract_signed = ct.ts_signed
  WHERE
    NOT ctp.id_user_contract_person IS NULL
    AND NOT ct.ts_signed IS NULL
    AND ct.is_active_or_ended = TRUE
    AND ctp.contract_role IN ('tenant', 'dweller')
), contracts_flows AS (
  SELECT
    *
  FROM tps_contracts
  UNION ALL
  SELECT
    *
  FROM contracts_person
  WHERE
    cs_order = 1
), contracts AS (
  SELECT
    NULL AS id_demand_prospect_conversion_event,
    id_tenant_prospect,
    'CONTRACT SIGNED' AS event_name,
    city_group,
    FALSE AS is_rent_flow_event,
    ts_contract_signed AS ts_event
  FROM contracts_flows
  WHERE
    NOT ts_contract_signed IS NULL
  UNION ALL
  SELECT
    NULL AS id_demand_prospect_conversion_event,
    cf1.id_tenant_prospect,
    'CONTRACT TERMINATED' AS event_name,
    cf1.city_group,
    FALSE AS is_rent_flow_event,
    cf1.ts_contract_terminated AS ts_event
  FROM contracts_flows AS cf1
  LEFT JOIN contracts_flows AS cf2 /* Filter all endings that occured when a new contract was active */
    ON cf1.id_tenant_prospect = cf2.id_tenant_prospect
    AND cf1.city_group = cf2.city_group
    AND cf1.ts_contract_signed < cf2.ts_contract_signed
    AND cf1.ts_contract_terminated > cf2.ts_contract_signed
  LEFT JOIN rent_flows AS rf /* Filter all endings that occured after a new activation */
    ON cf1.id_tenant_prospect = rf.id_tenant_prospect
    AND cf1.city_group = rf.city_group
    AND cf1.ts_contract_signed < rf.ts_event
    AND cf1.ts_contract_terminated > rf.ts_event
  WHERE
    NOT cf1.ts_contract_terminated IS NULL
    AND (
      NOT cf2.ts_contract_signed BETWEEN cf1.ts_contract_signed AND cf1.ts_contract_terminated
      OR cf2.id_tenant_prospect IS NULL
    )
    AND (
      NOT rf.ts_event BETWEEN cf1.ts_contract_signed AND cf1.ts_contract_terminated
      OR rf.id_tenant_prospect IS NULL
    )
), first_rent_flows_and_contract AS (
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    event_name,
    city_group,
    is_rent_flow_event,
    ts_event
  FROM rent_flows
  UNION ALL
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    event_name,
    city_group,
    is_rent_flow_event,
    ts_event
  FROM contracts
), lag_and_lead_dates AS (
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    event_name,
    city_group,
    is_rent_flow_event,
    ts_event,
    LAG(event_name) OVER (PARTITION BY id_tenant_prospect, city_group ORDER BY ts_event) AS previous_event_name,
    LAG(ts_event) OVER (PARTITION BY id_tenant_prospect, city_group ORDER BY ts_event) AS ts_previous_event,
    LEAD(ts_event) OVER (PARTITION BY id_tenant_prospect, city_group ORDER BY ts_event ASC, event_name DESC) AS ts_next_event
  FROM first_rent_flows_and_contract
), prospect_churn_rule AS (
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    city_group,
    event_name,
    previous_event_name,
    is_rent_flow_event,
    ts_event,
    ts_previous_event,
    ts_next_event,
    CASE
      WHEN event_name = 'CONTRACT SIGNED'
      THEN ts_event
      WHEN event_name = 'CONTRACT TERMINATED' AND previous_event_name = 'CONTRACT SIGNED'
      THEN ts_event
      WHEN is_rent_flow_event = TRUE
      AND DATEDIFF(TO_DATE(COALESCE(ts_next_event, CURRENT_DATE)), TO_DATE(ts_event)) > 28
      THEN DATE_ADD(ts_event, 28)
    END AS ts_prospect_churned
  FROM lag_and_lead_dates
), status_dates AS (
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    event_name,
    city_group,
    is_rent_flow_event,
    ts_event,
    ts_previous_event,
    ts_next_event,
    ts_prospect_churned,
    FIRST_VALUE(ts_prospect_churned) IGNORE NULLS OVER (PARTITION BY id_tenant_prospect, city_group ORDER BY ts_event ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS ts_next_prospect_churn
  FROM prospect_churn_rule
), churned_periods AS (
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    event_name,
    city_group,
    CASE WHEN event_name = 'CONTRACT SIGNED' THEN 'RENTED' ELSE 'CHURNED' END AS status,
    is_rent_flow_event,
    ts_prospect_churned AS ts_status_started,
    ts_next_event AS ts_status_ended
  FROM status_dates
  WHERE
    NOT ts_prospect_churned IS NULL
), active_periods_dates AS (
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    event_name,
    city_group,
    status,
    is_rent_flow_event,
    ts_event,
    ts_status_started,
    ts_status_ended
  FROM (
    SELECT
      id_demand_prospect_conversion_event,
      id_tenant_prospect,
      event_name,
      city_group,
      'ACTIVE' AS status,
      is_rent_flow_event,
      ts_event,
      MIN(ts_event) OVER (PARTITION BY id_tenant_prospect, city_group, ts_next_prospect_churn ORDER BY ts_event) AS ts_status_started,
      ts_next_prospect_churn AS ts_status_ended,
      ROW_NUMBER() OVER (PARTITION BY id_tenant_prospect, city_group, ts_next_prospect_churn ORDER BY ts_event) AS _w,
      ts_next_prospect_churn
    FROM status_dates
    WHERE
      is_rent_flow_event = TRUE
  ) AS _t
  WHERE
    ts_event /* Get only the event that started the active period */ = ts_status_started
    AND /* Remove corner cases where there are multiple activation event with the same exact timestamp */ _w = 1
), active_periods AS (
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    event_name,
    city_group,
    status,
    is_rent_flow_event,
    ts_status_started,
    ts_status_ended,
    MIN(ts_status_started) OVER (PARTITION BY id_tenant_prospect) AS ts_became_new_tenant_prospect, /* Get first activetion by client, */
    ROW_NUMBER() OVER (PARTITION BY id_tenant_prospect, city_group ORDER BY ts_status_started) AS activation_order /* Get first activetion by client and city group */
  FROM active_periods_dates
), base AS (
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    event_name,
    city_group,
    status,
    is_rent_flow_event,
    ts_status_started,
    ts_status_ended,
    CAST(NULL AS TIMESTAMP) AS ts_became_new_tenant_prospect,
    CAST(NULL AS INT) AS activation_order
  FROM churned_periods
  UNION ALL
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    event_name,
    city_group,
    status,
    is_rent_flow_event,
    ts_status_started,
    ts_status_ended,
    ts_became_new_tenant_prospect,
    activation_order
  FROM active_periods
), status_rules AS (
  SELECT
    id_demand_prospect_conversion_event,
    id_tenant_prospect,
    event_name AS status_trigger_event_name,
    CASE
      WHEN activation_order = 1 AND ts_status_started = ts_became_new_tenant_prospect
      THEN 'USER FIRST ACTIVATION'
      WHEN activation_order = 1
      AND LAG(status) OVER (PARTITION BY id_tenant_prospect ORDER BY ts_status_started) IN ('CHURNED', 'RENTED')
      THEN 'USER RECOVERY IN OTHER CITY GROUP'
      WHEN activation_order = 1
      THEN 'USER FIRST ACTIVATION IN CITY GROUP'
      WHEN status = 'RENTED'
      THEN 'USER DEACTIVATION BY CONTRACT SIGNED'
      WHEN status = 'CHURNED'
      THEN 'USER CHURN'
      WHEN LAG(status) OVER (PARTITION BY id_tenant_prospect, city_group ORDER BY ts_status_started) IN ('CHURNED', 'RENTED')
      THEN 'USER RECOVERY'
      ELSE NULL
    END AS prospect_event_name,
    city_group,
    FIRST(CASE WHEN ts_status_started = ts_became_new_tenant_prospect THEN city_group END) IGNORE NULLS OVER (PARTITION BY id_tenant_prospect ORDER BY ts_status_started ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS city_group_of_first_activation,
    status,
    CASE
      WHEN activation_order = 1 AND ts_status_started = ts_became_new_tenant_prospect
      THEN 'NEW TENANT PROSPECT'
      WHEN activation_order = 1
      THEN 'FIRST ACTIVATION IN CITY GROUP'
      WHEN status = 'ACTIVE'
      AND LAG(status) OVER (PARTITION BY id_tenant_prospect, city_group ORDER BY ts_status_started) = 'CHURNED'
      THEN 'RECOVERED AFTER CHURN'
      WHEN status = 'ACTIVE'
      AND LAG(status) OVER (PARTITION BY id_tenant_prospect, city_group ORDER BY ts_status_started) = 'RENTED'
      THEN 'RECOVERED AFTER RENTING'
      WHEN status IN ('CHURNED', 'RENTED') AND event_name = 'CONTRACT SIGNED'
      THEN 'DEACTIVATED BY RENTING'
      WHEN status IN ('CHURNED', 'RENTED') AND event_name = 'CONTRACT TERMINATED'
      THEN 'CONTRACT ENDED'
      WHEN status IN ('CHURNED', 'RENTED') AND is_rent_flow_event = TRUE
      THEN 'INACTIVITY'
    END AS status_detail,
    ts_status_started,
    ts_status_ended,
    MIN(ts_became_new_tenant_prospect) OVER (PARTITION BY id_tenant_prospect) AS ts_first_activation
  FROM base
)
SELECT
  id_demand_prospect_conversion_event,
  id_tenant_prospect,
  status_trigger_event_name,
  prospect_event_name,
  city_group,
  city_group_of_first_activation,
  status,
  status_detail,
  ts_status_started,
  ts_status_ended,
  ts_first_activation,
  YEAR(TO_DATE(ts_status_started)) AS year,
  MONTH(TO_DATE(ts_status_started)) AS month,
  DAY(TO_DATE(ts_status_started)) AS day
FROM status_rules
WHERE
  CAST(ts_status_started AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)