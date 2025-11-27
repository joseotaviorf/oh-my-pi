WITH concierge_events AS (
  SELECT
    csm.content,
    csm.ts_created,
    csm.id_session,
    css.id_user,
    css.user_phone_number,
    ebdb_user.id AS id_user_ebdb,
    CASE
      WHEN csm.content LIKE '%Olá! Gostaria de ver alguns imóveis no QuintoAndar%' THEN 'Facebook'
      WHEN csm.content LIKE '%QuintoAndar no portal%' THEN 'Online Classifieds'
      WHEN csm.content LIKE '%placa%' THEN 'Placas'
    END AS event_type
  FROM
    datalake_copilot_service_clean.message AS csm
  LEFT JOIN
    datalake_copilot_service_clean.session AS css
      ON csm.id_session = css.id
  LEFT JOIN
    datalake_ebdb_clean.user AS ebdb_user
      ON ebdb_user.main_phone = css.user_phone_number
  WHERE
    channel = 'WHATSAPP_CONCIERGE_CHAT'
    AND COALESCE(css.id_user, ebdb_user.id) IS NOT NULL
    AND message_index = 0
    AND role = 'HUMAN'
    AND (
      csm.content LIKE '%Olá! Gostaria de ver alguns imóveis no QuintoAndar%'
      OR csm.content LIKE '%QuintoAndar no portal%'
      OR csm.content LIKE '%placa%'
    )
)
SELECT
  COALESCE(id_user, id_user_ebdb) AS id_user,
  id_session AS id_contact,
  'Contact' AS event_name,
  event_type AS origin,
  event_type AS channel,
  'Concierge' AS agent,
  CASE
    -- Campanhas Facebook são Hybrid
    WHEN event_type = 'Facebook' THEN 'Hybrid'
    -- Online Classifieds e Placas verifica business_context na mensagem
    WHEN event_type IN ('Online Classifieds', 'Placas')
      AND (content LIKE '%alugar%' OR content LIKE '%rent%')
      AND (content LIKE '%comprar%' OR content LIKE '%vend%' OR content LIKE '%sell%')
      THEN 'Hybrid'
    WHEN event_type IN ('Online Classifieds', 'Placas')
      AND (content LIKE '%alugar%' OR content LIKE '%rent%')
      THEN 'Rent'
    WHEN event_type IN ('Online Classifieds', 'Placas')
      AND (content LIKE '%comprar%' OR content LIKE '%vend%' OR content LIKE '%sell%')
      THEN 'Sale'
    ELSE 'Hybrid'
  END AS business_context,
  content,
  ts_created AS ts_event,
  YEAR(ts_created) AS year,
  MONTH(ts_created) AS month,
  DAY(ts_created) AS day
FROM
  concierge_events
