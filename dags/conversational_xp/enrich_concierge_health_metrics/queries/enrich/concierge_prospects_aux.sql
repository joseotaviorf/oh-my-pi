WITH prospects AS (
  -- This CTE retrieves the prospect events such as activation and churn. This helps to identify if in the moment of concierge contact a user could become a prospect, i.e., if he/she was not previously an active prospect or had churned.
  SELECT DISTINCT 
    sk_prospect AS id_user,
    sk_house AS id_house,
    ts_event AS ts_prospect_event,
    CASE 
      WHEN event_name = 'USER FIRST ACTIVATION' THEN 'new_prospect'
      WHEN event_name IN ('USER RECOVERY', 'USER RECOVERY IN OTHER CITY GROUP') THEN 'recovered_prospect'
      WHEN event_name = 'USER CHURN' THEN 'prospect_churn'
    END AS prospect_event_type, 
    operation_channel, 
    UPPER(business_context) AS business_context
  FROM dw_growth.fact_demand_prospect_events
  WHERE event_name IN (
      'USER FIRST ACTIVATION',
      'USER RECOVERY',
      'USER RECOVERY IN OTHER CITY GROUP',
      'USER CHURN'
      ) -- These events indicate activation of the user (i.e. started a flow with a VB or DO) and the churn.
    AND flow_order = 1 -- Selecting the first event in that flow which is the combination of sk_prospect + sk_house.
    AND ts_event BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_90}) AND DATE('{end_date}') -- We are going further back in time for the prospect events to ensure that at moment of concierge contact the user was not previously an active prospect.
)

SELECT 
  c.id_user, 
  p.id_house,
  c.id_phone_session,
  c.concierge_flow_type,
  p.operation_channel AS prospect_activation_channel,
  p.business_context,
  p.prospect_event_type,
  CASE 
    WHEN prospect_event_type = 'prospect_churn' THEN TRUE
    ELSE FALSE 
  END AS is_contact_prospect,
  c.ts_concierge_contact,
  c.ts_message_sent,
  p.ts_prospect_event,
  YEAR(p.ts_prospect_event) AS year,
  MONTH(p.ts_prospect_event) AS month,
  DAY(p.ts_prospect_event) AS day
FROM datalake_search.concierge_messages c
JOIN prospects p
  ON p.id_user = c.id_user 
  AND DATE(p.ts_prospect_event) <= c.ts_concierge_contact 
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY c.id_user, c.ts_concierge_contact, c.concierge_flow_type
  ORDER BY p.ts_prospect_event DESC) = 1  