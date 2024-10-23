SELECT
  uniqueid AS id_contact,
  otheruniqueid AS id_other_unique,
  number AS phone_number,
  integrated AS id_integrated,
  channel,
  tipo AS type,
  status,
  total AS total_time,
  error,
  campaign,
  login AS agent_login,
  loginDestino AS destination_login,
  model,
  maxresponsedelay AS max_response_delay,
  repliedmessage AS replied_message,
  lasttext AS last_text,
  option1 AS option_1,
  option2 AS option_2,
  option3 AS option_3,
  option4 AS option_4,
  option5 AS option_5,
  option6 AS option_6,
  option7 AS option_7,
  option8 AS option_8,
  option9 AS option_9,
  dt AS ts_report,
  year,
  month,
  day
FROM
    datalake_hmb_ada_raw.report_5andar
WHERE
    DATE(dt) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')