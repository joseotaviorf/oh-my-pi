WITH call_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS id_ticket,
    MD5(
      CONCAT(
        COALESCE(step_tag, ''),
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, ''),
        COALESCE(contact_theme_detail_tag, '')
      )
    ) AS id_taxonomy,
    MD5(tags) AS id_tags,
    MD5(CONCAT('call', 'twilio', COALESCE(direction, ''))) AS id_channel,
    MD5(first_agent_email) AS id_first_agent,
    MD5(last_agent_email) AS id_last_agent,
    MD5(first_department) AS id_first_department,
    MD5(last_department) AS id_main_department,
    MAX(id_user) AS id_user,
    id_contract AS id_contract,
    id_session AS id_session,
    MD5("N/A") AS id_service_status,
    'call' AS channel,
    channel_type,
    direction,
    team,
    area,
    ticket_origin,
    contact_theme_tag AS theme,
    contact_theme_detail_tag AS theme_detail,
    last_csat_score AS csat_score,
    first_csat_score,
    status,
    first_department,
    last_department AS main_department,
    number_of_departments AS total_departments,
    number_of_segments AS total_segments,
    frt AS full_resolution_time,
    front_or_back,
    CAST(last_back_ticket AS BIGINT) AS last_back_ticket,
    back_ticket_list AS back_tickets,
    is_solved AS resolution_survey,
    IF(
      front_or_back = 'front'
      AND DATE(ts_ticket_ended) >= DATE('2022-01-01')
      AND contact_theme_detail_tag IS NOT NULL
      AND team <> 'Ong Back'
      AND area = 'CX'
      AND last_department NOT IN ('Rescisão por Inadimplência [OFF][POS][BACK]',
        'Offboarding Reparos [OFF] [POS] [BACK]',
        'Offboarding pré saída [OFF] [POS] [BACK]',
        'Proteção QuintoAndar [OFF] [POS] [BACK]',
        'Rescisão - Despejo [OFF][POS][BACK]',
        'Rescisão 1 [OFF] [POS] [BACK]'
      )
      AND ticket_origin IN ('call inapp', 'call inbound'),
      TRUE,
      FALSE
    ) AS is_ticket_rate,
    is_csat_answered AS has_answered_csat,
    has_back_ticket,
    is_open_back_ticket AS is_back_ticket_open,
    CASE
      WHEN is_solved = TRUE
          AND (back_ticket_list IS NULL OR is_open_back_ticket = FALSE)
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_solved,
    CASE
      WHEN is_solved = TRUE
          AND back_ticket_list IS NULL
          AND has_transfers = FALSE
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_fcr,
    has_transfers,
    total_minutes_reception_time,
    total_minutes_talk_time,
    total_minutes_queue_time,
    total_minutes_wrap_up_time,
    total_minutes_handling_time,
    total_backoffice_minutes_time,
    total_minutes_front_to_open_back_ticket_time,
    replies,
    reopens,
    NULL AS csat_comment,
    NULL AS first_csat_comment,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    ts_ticket_ended AS ts_solved,
    ts_csat_last_response AS ts_csat_response,
    ts_csat_first_response,
    ts_csat_last_response AS ts_survey
  FROM
    datalake_customer_support.call
  GROUP BY 1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55
),
chat_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS id_ticket,
    MD5(
      CONCAT(
        COALESCE(step_tag, ''),
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, ''),
        COALESCE(contact_theme_detail_tag, '')
      )
    ) AS id_taxonomy,
    MD5(tags) AS id_tags,
    MD5(CONCAT('chat', 'twilio')) AS id_channel,
    MD5(first_agent_email) AS id_first_agent,
    MD5(last_agent_email) AS id_last_agent,
    MD5(first_department) AS id_first_department,
    MD5(last_department) AS id_main_department,
    MAX(id_user) AS id_user,
    id_contract AS id_contract,
    id_session AS id_session,
    MD5(service_status) AS id_service_status,
    'chat' AS channel,
    NULL AS channel_type,
    NULL AS direction,
    team,
    area,
    ticket_origin,
    contact_theme_tag AS theme,
    contact_theme_detail_tag AS theme_detail,
    last_csat_score AS csat_score,
    first_csat_score,
    status,
    first_department,
    last_department AS main_department,
    number_of_departments AS total_departments,
    number_of_segments AS total_segments,
    frt AS full_resolution_time,
    front_or_back,
    CAST(last_back_ticket AS BIGINT) AS last_back_ticket,
    back_ticket_list AS back_tickets,
    is_solved AS resolution_survey,
    IF(
      front_or_back = 'front'
      AND DATE(ts_ticket_ended) >= DATE('2022-01-01')
      AND contact_theme_detail_tag IS NOT NULL
      AND team <> 'Ong Back'
      AND area = 'CX'
      AND last_department NOT IN ('Rescisão por Inadimplência [OFF][POS][BACK]',
        'Offboarding Reparos [OFF] [POS] [BACK]',
        'Offboarding pré saída [OFF] [POS] [BACK]',
        'Proteção QuintoAndar [OFF] [POS] [BACK]',
        'Rescisão - Despejo [OFF][POS][BACK]',
        'Rescisão 1 [OFF] [POS] [BACK]'
      ),
      TRUE,
      FALSE
    ) AS is_ticket_rate,
    is_csat_answered AS has_answered_csat,
    has_back_ticket,
    is_open_back_ticket AS is_back_ticket_open,
    CASE
      WHEN is_solved = TRUE
          AND (back_ticket_list IS NULL OR is_open_back_ticket = FALSE)
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_solved,
    CASE
      WHEN is_solved = TRUE
          AND back_ticket_list IS NULL
          AND number_of_departments <= 1
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_fcr,
    has_transfers,
    total_minutes_reception_time,
    total_minutes_talk_time,
    total_minutes_queue_time,
    total_minutes_wrap_up_time,
    total_minutes_handling_time,
    total_backoffice_minutes_time,
    total_minutes_front_to_open_back_ticket_time,
    replies,
    reopens,
    last_csat_comment AS csat_comment,
    first_csat_comment,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    ts_ticket_ended AS ts_solved,
    ts_csat_last_response AS ts_csat_response,
    ts_csat_first_response,
    ts_csat_last_response AS ts_survey
  FROM
    datalake_customer_support.chat
  GROUP BY 1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55
),
email_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS id_ticket,
    MD5(
      CONCAT(
        COALESCE(step_tag, ''),
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, ''),
        COALESCE(contact_theme_detail_tag, '')
      )
    ) AS id_taxonomy,
    MD5(tags) AS sk_tags,
    MD5(CONCAT('email', 'zendesk', COALESCE(direction, ''))) AS id_channel,
    MD5(agent_email) AS id_first_agent,
    MD5(agent_email) AS id_last_agent,
    MD5(department) AS id_first_department,
    MD5(department) AS id_main_department,
    MAX(id_user) AS id_user,
    id_contract AS id_contract,
    -1 AS id_session,
    MD5("N/A") AS id_service_status,
    'email' AS channel,
    NULL AS channel_type,
    direction,
    team,
    area,
    'N/A' AS ticket_origin,
    contact_theme_tag AS theme,
    contact_theme_detail_tag AS theme_detail,
    csat_score,
    first_csat_score,
    status,
    department AS first_department,
    department AS main_department,
    1 AS total_departments,
    1 AS total_segments,
    frt AS full_resolution_time,
    front_or_back,
    CAST(last_back_ticket AS BIGINT) AS last_back_ticket,
    back_ticket_list AS back_tickets,
    is_solved AS resolution_survey,
    IF(
      (
        front_or_back IN ('back', 'front')
        AND DATE(ts_ticket_solved) >= DATE('2022-01-01')
        AND contact_theme_detail_tag IS NOT NULL
        AND team <> 'Ong Back'
        AND area = 'CX'
        AND department NOT IN ('Rescisão por Inadimplência [OFF][POS][BACK]',
          'Offboarding Reparos [OFF] [POS] [BACK]',
          'Offboarding pré saída [OFF] [POS] [BACK]',
          'Proteção QuintoAndar [OFF] [POS] [BACK]',
          'Rescisão - Despejo [OFF][POS][BACK]',
          'Rescisão 1 [OFF] [POS] [BACK]'
        )
      )
      AND NOT (
        department = 'ReclameAqui [CE] [POS] [BACK]' 
        AND ticket_type = 'problem'
      ),
      TRUE,
      FALSE
    ) AS is_ticket_rate,
    is_answered AS has_answered_csat,
    has_back_ticket,
    is_open_back_ticket AS is_back_ticket_open,
    CASE
      WHEN is_solved = TRUE
          AND (back_ticket_list IS NULL OR is_open_back_ticket = FALSE)
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_solved,
    CASE
      WHEN is_solved = TRUE
          AND back_ticket_list IS NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_fcr,
    NULL AS has_transfers,
    NULL AS total_minutes_reception_time,
    NULL AS total_minutes_talk_time,
    NULL AS total_minutes_queue_time,
    NULL AS total_minutes_wrap_up_time,
    NULL AS total_minutes_handling_time,
    total_backoffice_minutes_time,
    total_minutes_front_to_open_back_ticket_time,
    replies,
    reopens,
    csat_comment,
    first_csat_comment,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    ts_ticket_solved AS ts_solved,
    ts_csat_last_response AS ts_csat_response,
    ts_csat_first_response,
    NULL AS ts_survey
  FROM
    datalake_customer_support.email
  GROUP BY 1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55
),
base_tickets AS (
  SELECT
    *
  FROM
    call_tickets
  UNION ALL
  SELECT
    *
  FROM
    email_tickets
  UNION ALL
  SELECT
    *
  FROM
    chat_tickets
),
session_contracts AS (
  SELECT
    id_session,
    CAST(GET_JSON_OBJECT(memory, "$.basic.user.contract.deeplink.contract_id") AS BIGINT) AS id_contract
  FROM
    datalake_greenseer_clean.session
  WHERE
    year >= 2024
    AND GET_JSON_OBJECT(memory, "$.basic.user.contract.deeplink.contract_id") IS NOT NULL
)
SELECT DISTINCT
    bt.id_ticket,
    bt.id_taxonomy,
    bt.id_tags,
    bt.id_channel,
    bt.id_first_agent,
    bt.id_last_agent,
    bt.id_first_department,
    bt.id_main_department,
    bt.id_user,
    COALESCE(sc.id_contract, bt.id_contract) AS id_contract,
    bt.id_session,
    bt.id_service_status,
    bt.channel,
    bt.channel_type,
    bt.direction,
    bt.team,
    bt.area,
    bt.ticket_origin,
    bt.theme,
    bt.theme_detail,
    CASE
      WHEN tr.sub_journey IN ('Contract to Entrance', 'Listing & Search', 'Offboarding', 'Onboarding', 'Visits to Offer') THEN 'ForRent'
      WHEN tr.sub_journey = 'For Sale' THEN 'ForSale'
      WHEN tr.sub_journey = 'Partners' THEN 'Partners'
      ELSE NULL
    END AS context,
    bt.csat_score,
    bt.first_csat_score,
    bt.status,
    bt.first_department,
    bt.main_department,
    bt.total_departments,
    bt.total_segments,
    bt.full_resolution_time,
    bt.front_or_back,
    bt.last_back_ticket,
    bt.back_tickets,
    bt.resolution_survey,
    CASE
      WHEN bt.is_ticket_rate AND tr.sub_journey = 'Ongoing' THEN
        CASE
          WHEN bt.front_or_back = 'front' THEN 15
          WHEN bt.front_or_back = 'back' THEN 30
        END
      WHEN bt.is_ticket_rate AND tr.sub_journey IN ('Contract to Entrance', 'For Sale',
        'Listing & Search', 'Offboarding', 'Onboarding', 'Partners', 'Visits to Offer') THEN
          CASE
            WHEN bt.front_or_back = 'front' THEN 1
            WHEN bt.front_or_back = 'back' THEN 2
          END
      ELSE NULL
    END AS ticket_rate_weight,
    bt.is_ticket_rate,
    bt.has_answered_csat,
    bt.has_back_ticket,
    bt.is_back_ticket_open,
    bt.is_solved,
    bt.is_fcr,
    bt.has_transfers,
    bt.total_minutes_reception_time,
    bt.total_minutes_talk_time,
    bt.total_minutes_queue_time,
    bt.total_minutes_wrap_up_time,
    bt.total_minutes_handling_time,
    bt.total_backoffice_minutes_time,
    bt.total_minutes_front_to_open_back_ticket_time,
    bt.replies,
    bt.reopens,
    SUBSTR(bt.csat_comment, 1, 1000) AS csat_comment,
    SUBSTR(bt.first_csat_comment, 1, 1000) AS first_csat_comment,
    bt.ts_started,
    bt.ts_closed,
    bt.ts_solved,
    bt.ts_csat_response,
    bt.ts_csat_first_response,
    bt.ts_survey
FROM
    base_tickets AS bt
LEFT JOIN
  datalake_gsheets_clean.ticket_rate_classification AS tr
    ON bt.theme_detail = tr.micro_taxonomy
      AND bt.theme = tr.macro_taxonomy
LEFT JOIN
  session_contracts AS sc
    ON sc.id_session = bt.id_session
