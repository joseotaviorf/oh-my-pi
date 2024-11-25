WITH tracking_hsm_answer_button_clicked AS (
  SELECT 
    GET_JSON_OBJECT(event_properties, '$.house_id') AS house_id,
    GET_JSON_OBJECT(event_properties, '$.template') AS template,
    GET_JSON_OBJECT(event_properties, '$.requested_action_consolidated') AS requested_action_consolidated,
    GET_JSON_OBJECT(event_properties, '$.requested_action_with_reason') AS requested_action_with_reason,
    GET_JSON_OBJECT(event_properties, '$.button_clicked_raw_text') AS button_clicked_raw_text,
    event_type,
    ts_event
  FROM 
    datalake_amplitude_clean.events AS e
  WHERE
    MAKE_DATE(e.year, e.month, e.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND e.id_app = 183047
    AND e.event_type = 'availability_check__hsm_answer_button_clicked'
)
SELECT 
  GET_JSON_OBJECT(ac.event_properties, '$.house_id') AS id_house,
  GET_JSON_OBJECT(ac.event_properties, '$.publication_availability_check_hsm_group') AS publication_availability_check_hsm_group,
  bc.requested_action_consolidated,
  bc.requested_action_with_reason,
  bc.button_clicked_raw_text,
  ac.ts_event AS ts_hsm_sent,
  bc.ts_event AS ts_hsm_answered,
  ac.year,
  ac.month,
  ac.day
FROM 
  datalake_amplitude_clean.events AS ac
LEFT JOIN 
  tracking_hsm_answer_button_clicked AS bc
    ON bc.house_id = GET_JSON_OBJECT(ac.event_properties, '$.house_id')
WHERE
  MAKE_DATE(ac.year, ac.month, ac.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  AND ac.id_app = 183047
  AND ac.event_type = 'availability_check__property_sent_for_availability_check'
  AND GET_JSON_OBJECT(ac.event_properties, '$.publication_availability_check_hsm_group') = 'withheld_for_hsm_check'