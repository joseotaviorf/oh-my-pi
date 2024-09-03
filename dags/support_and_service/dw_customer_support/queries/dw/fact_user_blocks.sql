WITH whatsapp_blocks AS (
  SELECT
  gs.id_user,
  'WHATSAPP' AS channel,
  COALESCE(ss.user_data:["user_phone"], ss.user_data:["user_email"]) AS user_data,
  GET_JSON_OBJECT(gs.memory, '$.business_rules.internal_chat.whatsapp_strategy') AS strategy,
  gs.ts_started AS ts_blocked
FROM
  datalake_greenseer.sessions AS gs
LEFT JOIN
  datalake_sauron_clean.session AS ss
    ON ss.id = gs.id_session
    AND MAKE_DATE(ss.year, ss.month, ss.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
WHERE
  GET_JSON_OBJECT(gs.memory, '$.business_rules.internal_chat.whatsapp_strategy') IS NOT NULL
  AND MAKE_DATE(gs.year, gs.month, gs.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
blocks AS (
  SELECT
    id_user,
    'IVR' AS channel,
    user_phone AS user_data,
    strategy,
    ts_requested AS ts_blocked
  FROM
    datalake_bigfone_clean.ivr_closed_history
  WHERE
    MAKE_DATE(YEAR(ts_requested), MONTH(ts_requested), DAY(ts_requested)) BETWEEN '{load_start_date}' AND '{load_end_date}'
  UNION ALL
  SELECT
    id_user,
    channel,
    user_data,
    CASE
      WHEN strategy = 'already_close' THEN 'ALREADY_CLOSED'
      ELSE UPPER(strategy)
    END AS strategy,
    ts_blocked
  FROM
    whatsapp_blocks
)
SELECT
  COALESCE(CAST(b.id_user AS BIGINT), -1) AS sk_user,
  bic.tenant_journey_step,
  bic.tenant_persona_step,
  bic.landlord_journey_step,
  bic.landlord_persona_step,
  b.channel,
  b.user_data,
  b.strategy,
  bic.is_tenant,
  bic.is_landlord,
  bic.is_pp_multi,
  bic.has_app_installed,
  bic.ts_last_app_installed AS ts_last_app_opened,
  b.ts_blocked,
  YEAR(b.ts_blocked) AS year,
  MONTH(b.ts_blocked) AS month,
  DAY(b.ts_blocked) AS day
FROM
  blocks AS b
LEFT JOIN
  datalake_ss_logic_model.user_ss_metrics AS bic
    ON bic.id_user = b.id_user
    AND bic.year = YEAR(b.ts_blocked)
    AND bic.month = MONTH(b.ts_blocked)
    AND bic.day = DAY(b.ts_blocked)
WHERE
  b.id_user IS NOT NULL
  OR b.user_data IS NOT NULL
