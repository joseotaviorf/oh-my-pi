SELECT DISTINCT
  id_call,
  id_lead,
  agent_user_name,
  agent_email,
  agent_profile,
  sales_company,
  campaign_name,
  campaign_type,
  olos_disposition,
  wololo_disposition,
  phone_number,
  dnis,
  phone_type,
  organization,
  duration_in_seconds,
  ts_call_started,
  ts_call_ended,
  year,
  month,
  day
FROM
  datalake_olos_dialer.outbound_contact_attempts
WHERE
  agent_profile IS NOT NULL
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY id_lead ORDER BY ts_call_started DESC) = 1