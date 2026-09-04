SELECT
  id_amplitude,
  id_user,
  id_event,
  id_session,
  uuid,
  GET_JSON_OBJECT(user_properties, '$.ab_beakman_onboarding_owner_flow_v2') AS ab_beakman_onboarding_owner_flow_v2,
  ts_event,
  ts_client_event,
  ts_client_uploaded,
  year,
  month,
  day
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = '170698' AND event_type = 'tap_intent_selection_register_property'
    AND year = {year} AND month = {month} AND day = {day}
