WITH concierge_indirect_vb AS (
  SELECT DISTINCT
    a.id_user,
    a.ep_house_id AS id_house,
    dv.id_visit,
    a.ep_visit_code AS visit_code,
    dv.business_context,
    dv.visit_request_channel,
    dv.dt_created AS ts_visit_created,
    TRUE AS is_indirect_visit_booked,
    dv.is_visit_completed,
    fv.sk_funnel_offer_submitted IS NOT NULL AS is_offer_submitted,
    fv.sk_funnel_offer_accepted IS NOT NULL AS is_offer_accepted,
    fv.sk_funnel_contract_signed IS NOT NULL AS is_contract_signed
  FROM datalake_amplitude_clean.170698_visit_schedule_confirmed_events AS a
  JOIN dw_visit.dim_visit AS dv
    ON dv.visit_code = a.ep_visit_code
  JOIN dw_visit.fact_visits fv
    ON dv.sk_visit = fv.sk_visit
  WHERE get_json_object(event_properties, '$.recset_showcase') = 'CONCIERGE_WHATSAPP'
  AND dv.dt_created BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
)

SELECT
    ivb.id_user,
    ivb.id_house,
    ivb.id_visit,
    c.id_phone_session,
    ivb.visit_code,
    COALESCE(c.concierge_flow_type, 'Unknown') AS concierge_flow_type,
    ivb.visit_request_channel,
    is_indirect_visit_booked,
    ivb.is_visit_completed,
    ivb.is_offer_submitted,
    ivb.is_offer_accepted,
    ivb.is_contract_signed,
    ivb.business_context,
    DATEDIFF(day, DATE(c.ts_message_sent), DATE(ivb.ts_visit_created)) AS days_msg2vb,
    c.ts_concierge_contact,
    c.ts_message_sent,
    ivb.ts_visit_created,
    YEAR(ivb.ts_visit_created) AS year,
    MONTH(ivb.ts_visit_created) AS month,
    DAY(ivb.ts_visit_created) AS day
FROM concierge_indirect_vb ivb
LEFT JOIN datalake_search.concierge_messages c
    ON ivb.id_user = c.id_user 
    AND c.ts_message_sent <= ivb.ts_visit_created
QUALIFY ROW_NUMBER() OVER (PARTITION BY ivb.visit_code ORDER BY ivb.ts_visit_created - COALESCE(c.ts_message_sent, ivb.ts_visit_created) ASC) = 1 -- If in the same message session there are many concierge_flow_types prior to the creation/change of the visit, it ties the visit to the last message.