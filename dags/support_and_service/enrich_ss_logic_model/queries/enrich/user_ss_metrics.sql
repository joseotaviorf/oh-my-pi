WITH persona_type_pivot AS (
  SELECT
    id_user,
    id_country,
    cpf AS id_personal_number,
    country_code,
    main_phone,
    name,
    email,
    is_active,
    is_blocked,
    dt_birth,
    ts_user_updated,
    ts_user_created,
    year,
    month,
    day,
    COALESCE(MAX(is_pp_multi), FALSE) AS is_pp_multi,
    MAX(CASE WHEN client_type = 'tenant' THEN TRUE ELSE FALSE END) AS is_tenant,
    MAX(CASE WHEN client_type = 'broker' THEN TRUE ELSE FALSE END) AS is_broker,
    MAX(CASE WHEN client_type = 'property_owner' THEN TRUE ELSE FALSE END) AS is_property_owner,
    MAX(CASE WHEN client_type = 'photographer' THEN TRUE ELSE FALSE END) AS is_photographer
  FROM
    datalake_user.persona_type
  WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
),
ticket_metric AS (
  WITH ticket_base AS (
    SELECT DISTINCT
      id_user,
      id_ticket,
      'email' AS origin,
      status,
      ts_ticket_started AS ts_started,
      ts_ticket_ended AS ts_solved
    FROM
      datalake_customer_support.email
    WHERE
      id_user > -1
      AND ts_ticket_started IS NOT NULL
    UNION ALL
    SELECT DISTINCT
      id_user,
      id_ticket,
      'call' AS origin,
      status,
      ts_ticket_started AS ts_started,
      ts_ticket_ended AS ts_solved
    FROM
      datalake_customer_support.call
    WHERE
      id_user > -1
      AND ts_ticket_started IS NOT NULL
    UNION ALL
    SELECT DISTINCT
      id_user,
      id_ticket,
      'chat' AS origin,
      status,
      ts_ticket_started AS ts_started,
      ts_ticket_ended AS ts_solved
    FROM
      datalake_customer_support.chat
    WHERE
      id_user > -1
      AND ts_ticket_started IS NOT NULL
    UNION ALL
    SELECT DISTINCT
      id_user,
      id_task AS id_ticket,
      'back' AS origin,
      status,
      ts_started,
      ts_completed AS ts_solved
    FROM
      datalake_customer_demand.base_tasks
    WHERE
      id_user > -1
      AND ts_started IS NOT NULL
  )
  SELECT
    id_user,
    CONCAT_WS(',',
      COLLECT_SET(
        DISTINCT CASE
          WHEN origin = 'back' AND status = 'open' THEN id_ticket
        END
      )
    ) AS back_ticket_list,
    MAX(
      CASE
        WHEN origin = 'back' AND status = 'open' THEN TRUE
        ELSE FALSE
      END
    ) AS has_open_back_ticket,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'back' AND status = 'open' THEN id_ticket
          END
    ) AS total_open_back_ticket,
    COUNT(
      DISTINCT
        CASE
          WHEN origin = 'back' AND status = 'open' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 7 day THEN id_ticket
        END
    ) AS total_open_back_ticket_7,
    COUNT(
      DISTINCT
        CASE
          WHEN origin = 'back' AND status = 'open' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 30 day THEN id_ticket
        END
    ) AS total_open_back_ticket_30,
    COUNT(
      DISTINCT
        CASE
          WHEN origin = 'back' AND status = 'open' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 90 day THEN id_ticket
        END
    ) AS total_open_back_ticket_90,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'email' THEN id_ticket
          END
    ) AS total_email_ticket,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'email' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 7 day THEN id_ticket
          END
    ) AS total_email_ticket_7,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'email' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 30 day THEN id_ticket
          END
    ) AS total_email_ticket_30,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'email' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 90 day THEN id_ticket
          END
    ) AS total_email_ticket_90,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'call' THEN id_ticket
          END
    ) AS total_call_ticket,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'call' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 7 day THEN id_ticket
          END
    ) AS total_call_ticket_7,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'call' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 30 day THEN id_ticket
          END
    ) AS total_call_ticket_30,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'call' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 90 day THEN id_ticket
          END
    ) AS total_call_ticket_90,
    COUNT(
      DISTINCT
        CASE
          WHEN origin = 'chat' THEN id_ticket
        END
    ) AS total_chat_ticket,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'chat' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 7 day THEN id_ticket
          END
    ) AS total_chat_ticket_7,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'chat' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 30 day THEN id_ticket
          END
    ) AS total_chat_ticket_30,
    COUNT(
        DISTINCT
          CASE
            WHEN origin = 'chat' AND DATE(ts_started) >= CURRENT_DATE() - INTERVAL 90 day THEN id_ticket
          END
    ) AS total_chat_ticket_90
  FROM
    ticket_base
  GROUP BY 1
),
contract_metric AS (
  SELECT DISTINCT
    id_user,
    TRUE AS has_active_contract,
    CONCAT_WS(',' , COLLECT_SET(id)) AS active_contracts,
    COUNT(DISTINCT id) AS total_active_contracts
  FROM
    datalake_ebdb_clean.contract
  WHERE
    status = 'Ativo'
  GROUP BY 1, 2
),
user_latest_app_event AS (
  SELECT
      COALESCE(id_user, -1) AS id_user,
      MAX(ts_event) AS ts_latest_event
  FROM
      datalake_app_installed.events
  GROUP BY 1
),
app_metric AS (
  SELECT
    id_user,
    CASE
      WHEN DATEDIFF(CURRENT_DATE(), ts_latest_event) <= 45 THEN TRUE
      ELSE FALSE
    END AS has_app_installed,
    ts_latest_event
  FROM
    user_latest_app_event
  WHERE
    id_user IS NOT NULL
)
SELECT
  ptp.id_user,
  ptp.id_country,
  COALESCE(ptp.id_personal_number, -1) AS id_personal_number,
  ptp.country_code,
  ptp.main_phone,
  ptp.name,
  ptp.email,
  COALESCE(NULLIF(cm.active_contracts, ''), 'not applicable') AS active_contracts,
  COALESCE(NULLIF(tm.back_ticket_list, ''), 'not applicable') AS back_ticket_list,
  COALESCE(tm.total_open_back_ticket, 0) AS total_open_back_ticket,
  COALESCE(tm.total_open_back_ticket_7, 0) AS total_open_back_ticket_7,
  COALESCE(tm.total_open_back_ticket_30, 0) AS total_open_back_ticket_30,
  COALESCE(tm.total_open_back_ticket_90, 0) AS total_open_back_ticket_90,
  COALESCE(tm.total_call_ticket, 0) AS total_call_ticket,
  COALESCE(tm.total_call_ticket_7, 0) AS total_call_ticket_7,
  COALESCE(tm.total_call_ticket_30, 0) AS total_call_ticket_30,
  COALESCE(tm.total_call_ticket_90, 0) AS total_call_ticket_90,
  COALESCE(tm.total_chat_ticket, 0) AS total_chat_ticket,
  COALESCE(tm.total_chat_ticket_7, 0) AS total_chat_ticket_7,
  COALESCE(tm.total_chat_ticket_30, 0) AS total_chat_ticket_30,
  COALESCE(tm.total_chat_ticket_90, 0) AS total_chat_ticket_90,
  COALESCE(tm.total_email_ticket, 0) AS total_email_ticket,
  COALESCE(tm.total_email_ticket_7, 0) AS total_email_ticket_7,
  COALESCE(tm.total_email_ticket_30, 0) AS total_email_ticket_30,
  COALESCE(tm.total_email_ticket_90, 0) AS total_email_ticket_90,
  COALESCE(cm.total_active_contracts, 0) AS total_active_contracts,
  ptp.is_pp_multi,
  ptp.is_tenant,
  ptp.is_broker,
  ptp.is_property_owner,
  ptp.is_photographer,
  ptp.is_active,
  ptp.is_blocked,
  COALESCE(tm.has_open_back_ticket, FALSE) AS has_open_back_ticket,
  COALESCE(cm.has_active_contract, FALSE) AS has_active_contract,
  COALESCE(am.has_app_installed, FALSE) AS has_app_installed,
  COALESCE(ptp.dt_birth, CAST('1900-01-01' AS TIMESTAMP)) AS dt_user_birth,
  COALESCE(am.ts_latest_event, CAST('1900-01-01' AS TIMESTAMP)) AS ts_app_latest_event,
  COALESCE(ptp.ts_user_updated, CAST('1900-01-01' AS TIMESTAMP)) AS ts_user_updated,
  COALESCE(ptp.ts_user_created, CAST('1900-01-01' AS TIMESTAMP)) AS ts_user_created,
  ptp.year,
  ptp.month,
  ptp.day
FROM
  persona_type_pivot AS ptp
LEFT JOIN
  ticket_metric AS tm
    ON tm.id_user = ptp.id_user
LEFT JOIN
  contract_metric AS cm
    ON cm.id_user = ptp.id_user
LEFT JOIN
  app_metric AS am
    ON am.id_user = ptp.id_user
