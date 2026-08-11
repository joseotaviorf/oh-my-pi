WITH prospect_info AS (
  SELECT
    id AS id_wololo_prospect,
    id_reference AS id_prospect,
    phone AS phone_number,
    REPLACE(phone, '+') AS phone_number_formated,
    status,
    mkt_origin,
    CAST(ts_created AS DATE) AS dt_prospect_created
  FROM datalake_wololo_clean.prospect
), user_notification_last_update AS (
  SELECT
    id,
    id_entity,
    entity_name,
    channel,
    template,
    tags,
    status,
    ts_sent,
    ts_created,
    ts_updated
  FROM (
    SELECT
      id,
      id_entity,
      entity_name,
      channel,
      template,
      tags,
      status,
      ts_sent,
      ts_created,
      ts_updated,
      ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w
    FROM datalake_jaiminho_clean.user_notifications
  ) AS _t
  WHERE
    _w = 1
), prospect_calls_last_update AS (
  SELECT
    id_wololo_prospect,
    id_prospect,
    id_call_analyst,
    phone_number,
    channel,
    call_output,
    round_number,
    call_number,
    round_max_tries,
    ts_contacted,
    ts_round_started,
    ts_load
  FROM (
    SELECT
      id_wololo_prospect,
      id_prospect,
      id_call_analyst,
      phone_number,
      channel,
      call_output,
      round_number,
      call_number,
      round_max_tries,
      ts_contacted,
      ts_round_started,
      ts_load,
      ROW_NUMBER() OVER (PARTITION BY id_prospect, ts_contacted ORDER BY ts_load DESC) AS _w
    FROM datalake_wololo_prospect.prospect_calls
  ) AS _t
  WHERE
    _w = 1
), canvas_step_details_last_update AS (
  SELECT
    id_canvas,
    id_step,
    canvas_name,
    step_name,
    step_message,
    ts_updated
  FROM (
    SELECT
      id_canvas,
      id_step,
      canvas_name,
      step_name,
      step_message,
      ts_updated,
      ROW_NUMBER() OVER (PARTITION BY id_step ORDER BY ts_updated DESC) AS _w
    FROM datalake_braze_details.canvas_step_details
    WHERE
      app_group = 'OWNERS'
      AND step_name <> 'Discard'
      AND (
        id_canvas /* OLD CANVAS */ = '9e5e5e97-dce0-41c2-84e2-ddda5f47db5d' /* P20 Price-Calculator PROD */
        OR id_canvas = 'ee490d54-e056-46c4-9084-407db97615cf' /* P20 Owner-PWA PROD */
        OR id_canvas = '37c43def-dee7-4df6-bd76-5fa2adc0b71a' /* P20 Indica-Aí PROD */
        OR /* NEW CANVAS */ id_canvas = '67988bb1-a9c8-4d25-838d-a94b0aa8aa6d' /* P20 Price-Calculator PROD */
        OR id_canvas = 'c004235d-e3f8-48aa-9f32-c93abcd25f75' /* P20 Owner-PWA PROD */
        OR id_canvas = '9364ace4-a1ff-44f3-a938-fdc8a8338507' /* P20 Indica-Aí PROD */
      )
  ) AS _t
  WHERE
    _w = 1
), braze_supply_events AS (
  SELECT
    wo.id_user_dispatch,
    wo.id_user_braze,
    CASE
      WHEN wo.id_user LIKE '%WOLOLO:%'
      THEN REGEXP_EXTRACT(wo.id_user, '(?<=WOLOLO:)(?s)(.*$)')
    END AS id_wololo_prospect,
    wo.id_canvas,
    wo.id_step_canvas,
    csd.canvas_name,
    csd.step_name AS canvas_step_name,
    NULLIF(REGEXP_EXTRACT(csd.step_message, '(?<=\\"max-tries":")(.*?)(?=")'), '') AS wololo_call_round_max_tries,
    NULLIF(REGEXP_EXTRACT(csd.step_message, '(?<=\\"entityId": ")(.*?)(?=",)'), '') AS jaimnho_entity_id_template,
    NULLIF(REGEXP_EXTRACT(csd.step_message, '(?<=}}_)(.*?)(?=")'), '') AS jaiminho_entity_name_sufix,
    wo.event_channel,
    wo.ts_webhook_sent,
    wo.year,
    wo.month,
    wo.day
  FROM datalake_braze_dispatches.webhook_owners AS wo
  INNER JOIN canvas_step_details_last_update AS csd
    ON wo.id_canvas = csd.id_canvas AND wo.id_step_canvas = csd.id_step
), jaiminho_keys AS (
  SELECT
    ppi.id_wololo_prospect,
    bse.id_step_canvas,
    CONCAT(ppi.phone_number_formated, '_', bse.jaiminho_entity_name_sufix) AS jaiminho_entity_name
  FROM prospect_info AS ppi
  INNER JOIN braze_supply_events AS bse
    ON ppi.id_wololo_prospect = bse.id_wololo_prospect
)
SELECT
  MD5(
    CONCAT(
      ppi.id_wololo_prospect,
      COALESCE(ppc.channel, un.channel, 'UNANSWERED_REQUEST'),
      COALESCE(ppc.ts_contacted, un.ts_sent, bse.ts_webhook_sent)
    )
  ) AS id_outbound_contact,
  ppi.id_wololo_prospect,
  ppi.id_prospect,
  bse.id_user_dispatch,
  bse.id_user_braze,
  bse.id_canvas,
  bse.id_step_canvas,
  bse.canvas_name,
  bse.canvas_step_name,
  ppi.phone_number,
  ppi.mkt_origin,
  CASE
    WHEN NOT ppc.channel IS NULL
    THEN UPPER(ppc.channel)
    WHEN NOT un.channel IS NULL
    THEN UPPER(un.channel)
    ELSE 'NONE'
  END AS contact_channel,
  CASE
    WHEN NOT un.channel IS NULL
    THEN MAP(
      'id_user_notification',
      un.id,
      'message_template',
      un.template,
      'tags',
      un.tags,
      'message_status',
      un.status,
      'whatsapp_opt_in',
      CAST(wpp.opt_in AS STRING)
    )
    WHEN NOT ppc.channel IS NULL
    THEN MAP(
      'id_call_analyst',
      ppc.id_call_analyst,
      'call_output',
      ppc.call_output,
      'call_number_in_round',
      ppc.call_number,
      'round_number',
      ppc.round_number,
      'round_max_tries',
      ppc.round_max_tries,
      'ts_call_round_started',
      ppc.ts_round_started
    )
  END AS contact_extra_info,
  ppi.dt_prospect_created,
  bse.ts_webhook_sent,
  COALESCE(un.ts_sent, ppc.ts_contacted) AS ts_contacted,
  NOW() AS ts_load,
  YEAR(TO_DATE(bse.ts_webhook_sent)) AS year,
  MONTH(TO_DATE(bse.ts_webhook_sent)) AS month,
  DAY(TO_DATE(bse.ts_webhook_sent)) AS day
FROM prospect_info AS ppi
INNER JOIN braze_supply_events AS bse
  ON ppi.id_wololo_prospect = bse.id_wololo_prospect
LEFT JOIN jaiminho_keys AS jk
  ON ppi.id_wololo_prospect = jk.id_wololo_prospect
  AND bse.id_step_canvas = jk.id_step_canvas
LEFT JOIN prospect_calls_last_update AS ppc
  ON ppi.id_wololo_prospect = ppc.id_wololo_prospect
  AND NOT bse.wololo_call_round_max_tries IS NULL
  AND CAST(bse.ts_webhook_sent AS DATE) = CAST(ppc.ts_round_started AS DATE)
LEFT JOIN user_notification_last_update AS un
  ON jk.jaiminho_entity_name = un.entity_name
  AND CAST(bse.ts_webhook_sent AS DATE) = CAST(un.ts_created AS DATE)
LEFT JOIN datalake_wololo_clean.whatsapp AS wpp
  ON ppi.phone_number = wpp.phone_number AND UPPER(un.channel) = 'WHATSAPP'
WHERE
  CAST(bse.ts_webhook_sent AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)