WITH prospects AS (
  -- This CTE retrieves the prospect events such as activation and churn. This helps to identify if in the moment of concierge contact a user could become a prospect, i.e., if he/she was not previously an active prospect or had churned.
  SELECT
    p.sk_prospect AS id_user,
    p.sk_house AS id_house,
    u.telefone_principal AS prospect_phone,
    p.ts_event AS ts_prospect_event,
    p.sk_visit AS id_visit,
    CASE
      WHEN p.event_name = 'USER FIRST ACTIVATION' THEN 'new_prospect'
      WHEN p.event_name IN ('USER RECOVERY', 'USER RECOVERY IN OTHER CITY GROUP') THEN 'recovered_prospect'
      WHEN p.event_name = 'USER CHURN' THEN 'prospect_churn'
    END AS prospect_event_type,
    p.operation_channel,
    UPPER(p.business_context) AS business_context
  FROM dw_growth.fact_demand_prospect_events AS p
  LEFT JOIN dw_public.dim_user u
    ON p.sk_prospect = u.sk_user
  WHERE p.event_name IN (
      'USER FIRST ACTIVATION',
      'USER RECOVERY',
      'USER RECOVERY IN OTHER CITY GROUP',
      'USER CHURN'
      ) -- These events indicate activation of the user (i.e. started a flow with a VB or DO) and the churn.
    AND p.flow_order = 1 -- Selecting the first event in that flow which is the combination of sk_prospect + sk_house.
    AND p.ts_event BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_120}) AND DATE('{end_date}') -- We are going further back in time for the prospect events to ensure that at moment of concierge contact the user was not previously an active prospect.
)

SELECT
  c.id_user,
  p.id_house,
  p.id_visit AS id_visit_prospect,
  c.id_phone_session,
  p.prospect_phone,
  c.concierge_flow_type,
  p.operation_channel AS prospect_activation_channel,
  p.business_context,
  p.prospect_event_type,
  c.ts_concierge_contact,
  c.ts_message_sent,
  p.ts_prospect_event,
  c.year,
  c.month,
  c.day
FROM datalake_search.concierge_messages c
JOIN prospects p
  -- some users have one phone number and more than one id_user. In some cases, in the visits table (where fact_demand_prospect_events gets information) has one id_user and in the concierge (copilot tables) has another id_user. Thus this join by phone number.
  ON (p.id_user = c.id_user OR p.prospect_phone = c.user_phone)
  AND DATE(p.ts_prospect_event) <= c.ts_concierge_contact
WHERE MAKE_DATE(c.year, c.month, c.day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY c.id_user, c.ts_concierge_contact, c.concierge_flow_type
  ORDER BY p.ts_prospect_event DESC) = 1
