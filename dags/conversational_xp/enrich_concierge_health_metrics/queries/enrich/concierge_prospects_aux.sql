WITH prospects AS (
  -- This CTE retrieves the prospect events such as activation and churn. This helps to identify if in the moment of concierge contact a user could become a prospect, i.e., if he/she was not previously an active prospect or had churned.
  SELECT
    sk_prospect AS id_user,
    sk_house AS id_house,
    ts_event AS ts_prospect_event,
    sk_visit AS id_visit,
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
    AND ts_event BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_120}) AND DATE('{end_date}') -- We are going further back in time for the prospect events to ensure that at moment of concierge contact the user was not previously an active prospect.
)

, messages_in_window AS (
  SELECT
    id_user,
    id_phone_session,
    user_phone,
    concierge_flow_type,
    ts_concierge_contact,
    ts_message_sent,
    year,
    month,
    day
  FROM datalake_search.concierge_messages
  WHERE MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
)

, phone2user AS (
  SELECT DISTINCT
    cr.id_reference AS id_user,
    ci.contact_info AS phone
  FROM datalake_person_clean.credential_reference cr
  JOIN datalake_person_clean.contact_info ci
    ON ci.id_person = cr.id_person
  WHERE ci.category = 'PHONE'
    AND ci.priority = 'PRIMARY'
    AND cr.origin = 'main'
    AND ci.contact_info IN (
      SELECT DISTINCT user_phone
      FROM messages_in_window
    )
)

, messages_resolved AS (
  SELECT
    c.id_user,
    c.id_phone_session,
    c.user_phone,
    c.concierge_flow_type,
    c.ts_concierge_contact,
    c.ts_message_sent,
    c.year,
    c.month,
    c.day,
    COALESCE(NULLIF(NULLIF(c.id_user, 0), -1), p2u.id_user) AS id_user_resolved
  FROM messages_in_window c
  LEFT JOIN phone2user p2u
    ON c.user_phone = p2u.phone
    AND NULLIF(NULLIF(c.id_user, 0), -1) IS NULL
)

, matched_prospects AS (
  SELECT
    p.id_user,
    p.id_house,
    p.id_visit AS id_visit_prospect,
    c.id_phone_session,
    c.user_phone AS prospect_phone,
    c.concierge_flow_type,
    p.operation_channel AS prospect_activation_channel,
    p.business_context,
    p.prospect_event_type,
    c.ts_concierge_contact,
    c.ts_message_sent,
    p.ts_prospect_event,
    c.year,
    c.month,
    c.day,
    ROW_NUMBER() OVER (
      PARTITION BY
        p.id_user,
        c.id_phone_session,
        c.ts_concierge_contact,
        c.concierge_flow_type
      ORDER BY p.ts_prospect_event DESC
    ) AS _row_num
  FROM messages_resolved c
  INNER JOIN prospects p
    ON p.id_user = c.id_user_resolved
    AND DATE(p.ts_prospect_event) <= c.ts_concierge_contact
)

SELECT
  id_user,
  id_house,
  id_visit_prospect,
  id_phone_session,
  prospect_phone,
  concierge_flow_type,
  prospect_activation_channel,
  business_context,
  prospect_event_type,
  ts_concierge_contact,
  ts_message_sent,
  ts_prospect_event,
  year,
  month,
  day
FROM matched_prospects
WHERE _row_num = 1
