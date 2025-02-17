WITH
  sale_flows AS (
    SELECT
      dpce.id_demand_prospect_conversion_event,
      dpce.id_prospect AS id_buyer_prospect,
      dpce.id_event_type,
      r.city_group,
      dpce.event_name,
      TRUE AS is_sale_flow_event,
      dpce.ts_event
    FROM
      datalake_demand_conversion_events_test.conversion_events AS dpce
    JOIN 
      datalake_sale_flows.sale_flow sf 
        ON sf.id_sale_flow = dpce.id_sale_flow
    LEFT JOIN 
      datalake_region.region AS r 
        ON dpce.id_region = r.id
    WHERE
      business_context = 'sale' 
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY
          id_prospect,
          dpce.id_house
        ORDER BY
          ts_event ASC
      ) = 1 -- Get only the first user's sale flow 
  ),
  sale_agreements AS (
    SELECT
      sde.id_buyer AS id_buyer_prospect,
      r.city_group,
      FALSE AS is_sale_flow_event,
      'SALE AGREEMENT SIGNED' AS event_name,
      sde.ts_event
    FROM
      datalake_sale_demand_events.sale_demand_events AS sde
    LEFT JOIN 
      datalake_region.region AS r 
        ON sde.id_region = r.id
    WHERE
      sde.sk_event_type = 6
      AND sde.id_buyer IS NOT NULL
  ),
  first_sale_flow_and_sale_agreements_signeds AS (
    SELECT
      id_demand_prospect_conversion_event,
      id_buyer_prospect,
      city_group,
      event_name,
      is_sale_flow_event,
      ts_event
    FROM
      sale_flows
    UNION ALL
    SELECT
      NULL AS id_demand_prospect_conversion_event,
      id_buyer_prospect,
      city_group,
      event_name,
      is_sale_flow_event,
      ts_event
    FROM
      sale_agreements
  ),
  lag_and_lead_dates AS (
    SELECT
      id_demand_prospect_conversion_event,
      id_buyer_prospect,
      city_group,
      event_name,
      is_sale_flow_event,
      ts_event,
      LAG(event_name) OVER (
        PARTITION BY
          id_buyer_prospect,
          city_group
        ORDER BY
          ts_event
      ) AS previous_event_name,
      LAG(ts_event) OVER (
        PARTITION BY
          id_buyer_prospect,
          city_group
        ORDER BY
          ts_event
      ) AS ts_previous_event,
      LEAD(ts_event) OVER (
        PARTITION BY
          id_buyer_prospect,
          city_group
        ORDER BY
          ts_event ASC,
          event_name DESC
      ) AS ts_next_event
    FROM
      first_sale_flow_and_sale_agreements_signeds
  ),
  prospect_churn_rule AS (
    SELECT
      id_demand_prospect_conversion_event,
      id_buyer_prospect,
      city_group,
      event_name,
      previous_event_name,
      is_sale_flow_event,
      ts_event,
      ts_previous_event,
      ts_next_event,
      CASE
        WHEN event_name = 'SALE AGREEMENT SIGNED' THEN ts_event
        WHEN DATEDIFF(COALESCE(ts_next_event, CURRENT_DATE), ts_event) > 90 THEN ts_event + INTERVAL 90 DAYS
        ELSE NULL
      END AS ts_prospect_churned
    FROM
      lag_and_lead_dates
  ),
  status_dates AS (
    SELECT
      id_demand_prospect_conversion_event,
      id_buyer_prospect,
      city_group,
      event_name,
      previous_event_name,
      is_sale_flow_event,
      ts_event,
      ts_previous_event,
      ts_next_event,
      ts_prospect_churned,
      FIRST_VALUE(ts_prospect_churned, TRUE) OVER (
        PARTITION BY
          id_buyer_prospect,
          city_group
        ORDER BY
          ts_event ROWS BETWEEN CURRENT ROW
          AND UNBOUNDED FOLLOWING
      ) AS ts_next_churn
    FROM
      prospect_churn_rule
  ),
  churned_periods AS (
    SELECT
      id_demand_prospect_conversion_event,
      id_buyer_prospect,
      city_group,
      event_name,
      is_sale_flow_event,
      CASE
        WHEN event_name = 'SALE AGREEMENT SIGNED' THEN 'SIGNED CCV'
        ELSE 'CHURNED'
      END AS status,
      ts_prospect_churned AS ts_status_started,
      ts_next_event AS ts_status_ended
    FROM
      status_dates
    WHERE
      ts_prospect_churned IS NOT NULL
  ),
  active_periods_dates AS (
    SELECT
      id_demand_prospect_conversion_event,
      id_buyer_prospect,
      city_group,
      event_name,
      is_sale_flow_event,
      'ACTIVE' AS status,
      MIN(ts_event) OVER (
        PARTITION BY
          id_buyer_prospect,
          city_group,
          ts_next_churn
        ORDER BY
          ts_event
      ) AS ts_status_started,
      ts_next_churn AS ts_status_ended
    FROM
      status_dates
    WHERE
      is_sale_flow_event = TRUE 
    QUALIFY
      -- Get only the event that started the active period
      ts_event = ts_status_started
      -- Remove corner cases where there are multiple activation event with the same exact timestamp
      AND ROW_NUMBER() OVER (
        PARTITION BY
          id_buyer_prospect,
          city_group,
          ts_next_churn
        ORDER BY
          ts_event
      ) = 1
  ),
  active_periods AS (
    SELECT
      id_demand_prospect_conversion_event,
      id_buyer_prospect,
      city_group,
      event_name,
      is_sale_flow_event,
      status,
      ts_status_started,
      ts_status_ended,
      MIN(ts_status_started) OVER (
        PARTITION BY
          id_buyer_prospect
      ) AS ts_became_new_buyer_prospect, -- Get first activetion by client,
      ROW_NUMBER() OVER (
        PARTITION BY
          id_buyer_prospect,
          city_group
        ORDER BY
          ts_status_started
      ) AS activation_order -- Get first activetion by client and city group
    FROM
      active_periods_dates
  ),
  base AS (
    SELECT
      id_demand_prospect_conversion_event,
      id_buyer_prospect,
      city_group,
      event_name,
      is_sale_flow_event,
      status,
      ts_status_started,
      ts_status_ended,
      CAST(NULL AS TIMESTAMP) AS ts_became_new_buyer_prospect,
      CAST(NULL AS INT) AS activation_order
    FROM
      churned_periods
    UNION ALL
    SELECT
      id_demand_prospect_conversion_event,
      id_buyer_prospect,
      city_group,
      event_name,
      is_sale_flow_event,
      status,
      ts_status_started,
      ts_status_ended,
      ts_became_new_buyer_prospect,
      activation_order
    FROM
      active_periods
  ),
  status_rules AS (
    SELECT
      id_demand_prospect_conversion_event,
      id_buyer_prospect,
      event_name AS status_trigger_event_name,
      CASE
        WHEN activation_order = 1
        AND ts_status_started = ts_became_new_buyer_prospect THEN 'USER FIRST ACTIVATION'
        WHEN activation_order = 1
        AND LAG(status) OVER (
          PARTITION BY
            id_buyer_prospect
          ORDER BY
            ts_status_started
        ) IN ('CHURNED', 'RENTED') THEN 'USER RECOVERY IN OTHER CITY GROUP'
        WHEN activation_order = 1 THEN 'USER FIRST ACTIVATION IN CITY GROUP'
        WHEN status = 'SIGNED CCV' THEN 'USER DEACTIVATION BY CCV SIGNED'
        WHEN status = 'CHURNED' THEN 'USER CHURN'
        WHEN LAG(status) OVER (
          PARTITION BY
            id_buyer_prospect,
            city_group
          ORDER BY
            ts_status_started
        ) IN ('CHURNED', 'SIGNED CCV') THEN 'USER RECOVERY'
        ELSE NULL
      END AS prospect_event_name,
      city_group,
      FIRST_VALUE(
        CASE
          WHEN ts_status_started = ts_became_new_buyer_prospect THEN city_group
        END
      ) OVER (
        PARTITION BY
          id_buyer_prospect
        ORDER BY
          ts_status_started ROWS UNBOUNDED PRECEDING
      ) AS city_group_of_first_activation,
      status,
      CASE
        WHEN activation_order = 1
        AND ts_status_started = ts_became_new_buyer_prospect THEN 'NEW BUYER PROSPECT'
        WHEN activation_order = 1 THEN 'FIRST ACTIVATION IN CITY GROUP'
        WHEN status = 'SIGNED CCV' THEN 'DEACTIVATED BY SINING SALE AGREEMENT'
        WHEN status = 'CHURNED' THEN 'CHURNED BY INACTIVITY'
        WHEN status = 'ACTIVE'
        AND LAG(status) OVER (
          PARTITION BY
            id_buyer_prospect,
            city_group
          ORDER BY
            ts_status_started
        ) = 'CHURNED' THEN 'RECOVERED AFTER CHURN'
        WHEN status = 'ACTIVE'
        AND LAG(status) OVER (
          PARTITION BY
            id_buyer_prospect,
            city_group
          ORDER BY
            ts_status_started
        ) = 'SIGNED CCV' THEN 'RECOVERED AFTER SALE AGREEMENT SIGNED'
        ELSE NULL
      END AS status_detail,
      ts_status_started,
      ts_status_ended,
      ts_became_new_buyer_prospect,
      MIN(ts_became_new_buyer_prospect) OVER (
        PARTITION BY
          id_buyer_prospect
      ) AS ts_first_activation
    FROM
      base
  )
SELECT
  id_demand_prospect_conversion_event,
  id_buyer_prospect,
  status_trigger_event_name,
  prospect_event_name,
  city_group,
  city_group_of_first_activation,
  status,
  status_detail,
  ts_status_started,
  ts_status_ended,
  ts_first_activation,
  YEAR(ts_status_started) AS year,
  MONTH(ts_status_started) AS month,
  DAY(ts_status_started) AS day
FROM
  status_rules
WHERE
  DATE(ts_status_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')