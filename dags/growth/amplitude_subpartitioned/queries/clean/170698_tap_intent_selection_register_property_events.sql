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
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )
