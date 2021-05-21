WITH tasks AS (
  WITH last_updated_reservations AS (
    SELECT
        id_reservation,
        MAX(DATE(CONCAT(year, '-', month, '-', day))) AS dt_last_updated
    FROM
        datalake_bigfone_twilio.call_flex_reservations
    GROUP BY 1
  ),
  twilio_timestamp AS (
    SELECT
        id_reservation,
        ts_created_local AS ts_twilio_created_local,
        ts_created_utc AS ts_twilio_created_utc
    FROM
        datalake_bigfone_twilio.call_flex_events
    WHERE
        event_type = 'reservation.accepted'
    GROUP BY 1,2,3
  ),
  task_closed AS (
    SELECT
        GET_JSON_OBJECT(metadata,'$.event_data.ReservationSid') AS id_reservation,
        FROM_UTC_TIMESTAMP(TO_TIMESTAMP(event_timestamp, 'yyyy-MM-dd HH:mm:ss'), 'Brazil/East') AS ts_closed
    FROM
        datalake_bigfone_clean.event
    WHERE
        event IN ('reservation.completed', 'reservation.timeout', 'reservation.canceled', 'reservation.rejected')
    GROUP BY 1,2
  )
  SELECT
    r.id_reservation,
    COALESCE(id_call,id_task) AS sk_call,
    id_call,
    id_task,
    id_agent,
    id_queue,
    queue_name,
    seconds_duration,
    seconds_wait_time,
    seconds_talk_time,
    is_answered,
    is_timeout,
    is_rejected,
    lur.dt_last_updated AS dt_updated,
    ts_created,
    ts_ended,
    tt.ts_twilio_created_local,
    tt.ts_twilio_created_utc,
    tc.ts_closed
  FROM
    datalake_bigfone_twilio.call_flex_reservations r
  INNER JOIN
    last_updated_reservations lur
        ON lur.id_reservation = r.id_reservation
        AND lur.dt_last_updated = DATE(CONCAT(r.year, '-', r.month, '-', r.day))
  LEFT JOIN
    twilio_timestamp tt
        ON tt.id_reservation = r.id_reservation
  LEFT JOIN
    task_closed tc
        ON tc.id_reservation = r.id_reservation
),
call AS (
  WITH ivr_events AS (
      SELECT
          id_call,
          from_number,
          to_number,
          customer_phone,
          UNIX_TIMESTAMP(MAX(ts_created_local)) - UNIX_TIMESTAMP(MIN(ts_created_local)) AS initial_ivr_time,
          MIN(id_task) AS id_task, -- workaround to filter 1 instance with duplicity
          MIN(ts_created_local) AS ts_first_event,
          MAX(ts_created_local) AS ts_last_event,
          MIN(ts_created_local_unix) AS ts_first_event_local_unix,
          MAX(ts_created_local_unix) AS ts_last_event_local_unix
      FROM
          datalake_bigfone_twilio.call_ivr_events
      GROUP BY 1,2,3,4
  ),
  call_events AS (
      SELECT
          id_task,
          id_call,
          id_conversation,
          customer_phone,
          from_number,
          to_number,
          direction,
          is_scheduled,
          scheduling_source,
          MIN(ts_created_local) AS ts_first_event,
          MAX(ts_created_local) AS ts_last_event,
          MIN(ts_created_local_unix) AS ts_first_event_local_unix,
          MAX(ts_created_local_unix) AS ts_last_event_local_unix,
          MAX(ts_wrapup_event_local_unix) AS ts_wrapup_event_local_unix
      FROM
          datalake_bigfone_twilio.call_flex_events
      WHERE
          event_type != 'task.updated'
      GROUP BY 1,2,3,4,5,6,7,8,9
  ),
  csat_events AS (
      SELECT
          id_call,
          id_task,
          MAX(csat_1) AS csat_1,
          MAX(csat_2) AS csat_2,
          MIN(ts_created_local) AS ts_csat
      FROM
          datalake_bigfone_twilio.call_ivr_events
      WHERE
          COALESCE(csat_1, csat_2) IS NOT NULL
      GROUP BY 1,2
  ),
  call_metrics AS (
      SELECT
          id_task,
          id_call,
          COUNT(DISTINCT queue_name) AS number_of_departments,
          COUNT(DISTINCT id_reservation) AS number_of_tasks,
          COUNT(id_reservation) AS reservations,
          SUM(CAST(is_answered AS SMALLINT)) AS reservations_accepted,
          SUM(seconds_wait_time) AS wait_time_flex,
          SUM(seconds_talk_time) AS talk_time,
          MIN(ts_created) AS ts_first_reservation,
          MAX(ts_created) AS ts_last_reservation
      FROM
          datalake_bigfone_twilio.call_flex_reservations
      GROUP BY 1,2
  )
  SELECT
      COALESCE(ie.id_call, fe.id_call) AS id_call,
      COALESCE(ie.id_call, fe.id_call, fe.id_conversation, fe.id_task) AS sk_call,
      fe.id_conversation,
      fe.id_task,
      COALESCE(ie.from_number,fe.from_number) AS from_phone_number,
      COALESCE(ie.to_number,fe.to_number) AS to_phone_number,
      ie.initial_ivr_time AS seconds_ivr_time,
      fe.direction,
      fe.scheduling_source,
      COALESCE(cm.number_of_tasks,0) AS number_of_tasks,
      COALESCE(cm.number_of_departments,0) AS number_of_departments,
      cm.reservations IS NULL AS has_ended_in_ura,
      cm.reservations_accepted > 0 AS is_answered,
      cm.reservations > 1 AS is_transfered,
      cm.wait_time_flex AS seconds_total_wait_time,
      cm.talk_time AS seconds_total_talk_time,
      ce.csat_2 IS NOT NULL AS is_csat_answered,
      ce.csat_1 = 1 AS is_solved,
      ce.csat_2 AS csat_rating,
      GREATEST(ie.ts_last_event_local_unix,fe.ts_last_event_local_unix) - COALESCE(ie.ts_first_event_local_unix,fe.ts_first_event_local_unix) AS seconds_duration,
      COALESCE(ie.ts_first_event,fe.ts_first_event) AS ts_started,
      ce.ts_csat AS ts_csat_answered,
      GREATEST(ie.ts_last_event,fe.ts_last_event) AS ts_ended,
      cfe.ts_created_local AS ts_created
  FROM
      ivr_events ie
  FULL JOIN
      call_events fe
          ON fe.id_call = ie.id_call
  LEFT JOIN 
      datalake_bigfone_twilio.call_flex_events cfe
          ON fe.id_task = cfe.id_task
  LEFT JOIN
      csat_events ce
          ON ce.id_call = ie.id_call
  LEFT JOIN
      call_metrics cm
          ON cm.id_task = fe.id_task
),
zendesk AS (
  WITH last_update_ticket AS (
    SELECT 
      id_ticket, 
      MAX(ts_updated) AS ts_last_updated 
    FROM 
      datalake_zendesk_tickets_clean.tickets
    GROUP BY 1
  ),
  filtered_custom_fields AS (
    SELECT
      zcf.id_ticket,
      EXPLODE(SPLIT(REPLACE(REPLACE(custom_fields, '{{', ''), '}}', ''), ',')) AS custom_field
    FROM 
      datalake_clean.zendesk_custom_fields zcf
  ),
  parsed_custom_fields AS (
    SELECT DISTINCT
      id_ticket,
      REGEXP_EXTRACT(custom_field, '"(.*)":(.*)', 1) AS id_ticket_fields,
      REPLACE(REGEXP_EXTRACT(custom_field, '"(.*)":(.*)', 2), '"', '') AS value,
      tf.raw_title AS key
    FROM 
      filtered_custom_fields tcf
    JOIN
      datalake_zendesk_tickets_clean.ticket_fields tf
        ON tf.id_ticket_fields = regexp_extract(custom_field, '"(.*)":(.*)', 1)
  ),
  zendesk_custom_fields AS (
    SELECT
      id_ticket,
      TO_JSON(MAP_FROM_ARRAYS(COLLECT_LIST(key), COLLECT_LIST(value))) AS custom_fields
    FROM
      parsed_custom_fields
    GROUP BY 1
  ),
  last_updated_ticket_metrics AS (
    SELECT
      t.id_ticket, 
      MAX(DATE(CONCAT(year, '-', month, '-', day))) AS dt_last_updated,
      MAX(ts_updated) AS ts_updated
    FROM 
      datalake_zendesk_ticket_funnels.tickets_funnel_metrics t
    GROUP BY 1
  )
  SELECT
    t.id_ticket,
    CASE
          WHEN 
              t.ticket_via IN ('api', 'web') 
              AND (tags LIKE '%call_contato_ativo%' OR tags LIKE '%call_contato_receptivo%') 
          THEN 'call'
          WHEN t.ticket_via = 'api' AND tags LIKE '%form%' THEN 'form_faq'
          WHEN t.ticket_via IN ('web', 'email', 'chat') THEN t.ticket_via
          ELSE 'other'
    END AS channel,
    t.tags,
    t.description,
    t.status,
    zcf.custom_fields,
    NULLIF(GET_JSON_OBJECT(REPLACE(REPLACE(zcf.custom_fields, ']',''), '[', ''), '$.CALL Call id'), '') AS id_call,
    tfm.minutes_first_resolution_calendar AS minutes_first_resolution_time_calendar,
    tfm.minutes_first_resolution_business AS minutes_first_resolution_time_business,
    REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Motivo de contato'), '[', ''), ']', '') AS contact_type_tag,
    REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Cliente Tag'), '[', ''), ']', '') AS client_type,
    REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Tipo de Solicitação'), '[', ''), ']', '') AS request_type,
    COALESCE(
      ctt.contact_motivation_tag,
      REPLACE(REPLACE(get_json_object(zcf.custom_fields, '$.Motivo Tag'), '[', ''), ']', '')
    ) AS contact_motivation_tag,
    COALESCE(
      ctt.contact_theme_tag,
      REPLACE(REPLACE(get_json_object(zcf.custom_fields, '$.Assunto Tag'), '[', ''), ']', '')
    ) AS contact_theme_tag
  FROM
    datalake_zendesk_tickets_clean.tickets t
  JOIN
    last_update_ticket lut
      ON t.id_ticket = lut.id_ticket
      AND t.ts_updated = lut.ts_last_updated
  JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics tfm
      ON t.id_ticket = tfm.id_ticket
  JOIN
    last_updated_ticket_metrics lutm
      ON lutm.id_ticket = tfm.id_ticket
      AND lutm.dt_last_updated = DATE(CONCAT(tfm.year, '-', tfm.month, '-', tfm.day))
      AND lutm.ts_updated = tfm.ts_updated
  JOIN
    zendesk_custom_fields zcf
      ON zcf.id_ticket = t.id_ticket
  LEFT JOIN
    datalake_gsheets_clean.contact_type_taxonomy ctt 
      ON ctt.contact_type_tag = REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Motivo de contato'), '[', ''), ']', '')
      AND ctt.is_correspondent_contact_type = 1
),
back_tickets AS (
  SELECT 
    REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})',1) AS front_task,
    zd.id_ticket AS back_ticket,
    zd.status,
    zd2.id_ticket AS front_ticket
  FROM
    zendesk zd
  JOIN
    call
      ON call.id_task = REGEXP_EXTRACT(description, '(WT[a-z0-9]{{20,40}})',1)
  JOIN  
    zendesk zd2
      ON zd2.id_call = call.sk_call
  WHERE 
    zd.tags LIKE '%tarefa_atendimento_escalado%'
    AND (zd.tags NOT LIKE '%bot_end_conversation%' AND zd.tags NOT LIKE '%closed_by_merge%')
    AND REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})',1) != '' 
)
SELECT
  DISTINCT zd.id_ticket,
  t.id_task,
  t.id_reservation,
  t.id_call,
  c.id_conversation,
  t.id_agent,
  t.id_queue,
  t.queue_name AS department,
  FIRST(t.queue_name) OVER (PARTITION BY c.id_task ORDER BY c.ts_created) AS first_department,
  LAST(t.queue_name) OVER (PARTITION BY c.id_task ORDER BY c.ts_created) AS last_department,
  CASE
      WHEN seconds_total_wait_time <= 60 AND t.is_answered THEN TRUE
      WHEN seconds_total_wait_time > 60 AND t.is_answered THEN FALSE
      ELSE NULL
  END AS sla_achieved,
  t.seconds_duration/60.0 AS task_minutes_duration,
  t.seconds_wait_time/60.0 AS task_minutes_wait_time,
  c.seconds_duration/60.0 AS minutes_full_resolution_time_calendar,
  c.number_of_departments,
  c.number_of_tasks,
  zd.minutes_first_resolution_time_calendar,
  zd.minutes_first_resolution_time_business,
  zd.contact_type_tag,
  zd.client_type,
  zd.request_type,
  zd.contact_motivation_tag,
  zd.contact_theme_tag,
  zd.tags,
  zd.status,
  zd.custom_fields,
  zd.tags LIKE '%tarefa_atendimento_escalado%' AS has_back_tickets,
  zd.tags LIKE '%bot_end_conversation%' AS is_bot, 
  zd.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
  c.has_ended_in_ura = FALSE AND t.is_answered = TRUE AS is_answered,
  bt.front_ticket IS NOT NULL AS has_back_ticket,
  CASE
    WHEN bt.status IN ('open','pending','new','hold') THEN TRUE
    WHEN bt.status IN ('closed','deleted','solved') THEN FALSE
  END AS is_open_back_ticket,
  CASE
    WHEN c.is_transfered = TRUE THEN TRUE
    ELSE FALSE
  END AS has_transfers,
  bt.back_ticket,
  c.is_csat_answered,
  c.is_solved,
  c.csat_rating,
  c.ts_csat_answered,
  t.ts_twilio_created_local AS ts_task_created,
  t.ts_closed AS ts_task_closed,
  c.ts_started AS ts_ticket_started,
  c.ts_ended AS ts_ticket_ended
FROM 
  tasks t
JOIN 
  call c
    ON t.sk_call = c.sk_call
JOIN 
  zendesk zd 
    ON zd.id_call IS NOT NULL
    AND zd.id_call = c.id_call
LEFT JOIN
  back_tickets bt
    ON bt.front_ticket = zd.id_ticket
WHERE
  zd.tags NOT LIKE '%tarefa_atendimento_escalado%'
