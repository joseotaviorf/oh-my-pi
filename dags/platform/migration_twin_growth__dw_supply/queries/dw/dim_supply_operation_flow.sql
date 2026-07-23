WITH events AS (
  SELECT 
    ops_objective, 
    ops_agent, 
    ops_partner, 
    ops_contact_medium, 
    ops_approach,
    REPLACE(ops_assigned, 'quinto_andar_outbound', 'quinto_andar') AS ops_assigned,
    MAX(ts_event_adjusted) AS last_ts_event
  FROM 
    datalake_supply_flows.supply_events_tracking
  GROUP BY ALL
)

SELECT
  CONCAT_WS('#',
    LEFT(COALESCE(ops_objective,'non') ,3),
    LEFT(REGEXP_REPLACE(COALESCE(ops_agent,'non'), 'is_',''), 3),
    LEFT(COALESCE(ops_partner, 'non'), 3),
    LEFT(COALESCE(ops_contact_medium, 'non'), 3),
    LEFT(COALESCE(ops_approach, 'non'), 3),
    LEFT(COALESCE(ops_assigned, 'non'), 3)
  ) AS bk_ops,
  ops_objective AS ds_objective, 
  ops_agent AS nm_agent, 
  ops_partner AS nm_partner, 
  ops_assigned AS nm_assigned_partner,
  ops_contact_medium AS cd_contact_medium, 
  ops_approach AS cd_approach,
  NOW() AS ts_updated
FROM events
QUALIFY ROW_NUMBER() OVER (PARTITION BY bk_ops ORDER BY last_ts_event DESC) = 1