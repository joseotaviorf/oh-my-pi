WITH
  rent_flow_events AS (
    SELECT
      CAST(cdp_tx.id_event AS VARCHAR) AS id_event,
      TRY_CAST(cdp_tx.id_user AS BIGINT) AS id_user,
      CAST(cdp_tx.id_person AS VARCHAR) AS uuid_user,
      TRY_CAST(JSON_EXTRACT_SCALAR(cdp_tx.event_properties, '$.id_house') AS BIGINT) AS id_house,
      JSON_EXTRACT_SCALAR(cdp_tx.event_properties, '$.id_rent_flow') AS id_rent_flow,
      TRY_CAST(JSON_EXTRACT_SCALAR(cdp_tx.event_properties, '$.id_documentation') AS BIGINT) AS id_proposal,
      cdp_tx.event_name,
      cdp_tx.ts_event
    FROM
      datalake_cdp_clean.transactional AS cdp_tx
    WHERE
      cdp_tx.application = 'rental-offer'
      AND cdp_tx.journey_step = 'documentation'
      AND cdp_tx.event_name IN (
        'rent_flow_tenant_credit_positive',
        'rent_flow_tenant_credit_positive_with_guarantee',
        'rent_flow_tenant_documentation_submitted',
        'rent_flow_documentation_canceled'
      )
      AND cdp_tx.id_user IS NOT NULL
      AND cdp_tx.id_person IS NOT NULL
      AND (
        YEAR > YEAR(CURRENT_DATE - INTERVAL '10' DAY)
        OR (
          YEAR = YEAR(CURRENT_DATE - INTERVAL '10' DAY)
          AND MONTH > MONTH(CURRENT_DATE - INTERVAL '10' DAY)
        )
        OR (
          YEAR = YEAR(CURRENT_DATE - INTERVAL '10' DAY)
          AND MONTH = MONTH(CURRENT_DATE - INTERVAL '10' DAY)
          AND DAY >= DAY(CURRENT_DATE - INTERVAL '10' DAY)
        )
      )
      AND ts_event >= CURRENT_TIMESTAMP - INTERVAL '10' DAY
  ),
  credit_positive_ranked AS (
    SELECT
      rfe.id_event,
      rfe.id_user,
      rfe.uuid_user,
      rfe.id_house,
      rfe.id_rent_flow,
      rfe.id_proposal,
      rfe.ts_event AS ts_credit_positive,
      ROW_NUMBER() OVER (
        PARTITION BY rfe.uuid_user,
        rfe.id_rent_flow
        ORDER BY
          rfe.ts_event DESC
      ) AS rn
    FROM
      rent_flow_events AS rfe
    WHERE
      rfe.event_name IN (
        'rent_flow_tenant_credit_positive',
        'rent_flow_tenant_credit_positive_with_guarantee'
      )
      AND rfe.id_event IS NOT NULL
      AND rfe.id_proposal IS NOT NULL
      AND rfe.id_rent_flow IS NOT NULL
  ),
  credit_positive_flows AS (
    SELECT
      cpr.id_event,
      cpr.id_user,
      cpr.uuid_user,
      cpr.id_house,
      cpr.id_rent_flow,
      cpr.id_proposal,
      cpr.ts_credit_positive
    FROM
      credit_positive_ranked AS cpr
    WHERE
      cpr.rn = 1
  ),
  rent_flow_flags AS (
    SELECT
      rfe.uuid_user,
      rfe.id_rent_flow,
      MAX(
        CASE
          WHEN rfe.event_name = 'rent_flow_tenant_documentation_submitted' THEN TRUE
          ELSE FALSE
        END
      ) AS documentation_sent,
      MAX(
        CASE
          WHEN rfe.event_name = 'rent_flow_documentation_canceled' THEN TRUE
          ELSE FALSE
        END
      ) AS has_documentation_canceled,
      MAX(
        CASE
          WHEN rfe.event_name = 'rent_flow_tenant_documentation_submitted' THEN rfe.ts_event
          ELSE NULL
        END
      ) AS ts_documentation_sent
    FROM
      rent_flow_events AS rfe
    WHERE
      rfe.id_rent_flow IS NOT NULL
    GROUP BY
      rfe.uuid_user,
      rfe.id_rent_flow
  ),
  eligible_flows AS (
    SELECT
      cpf.id_event,
      cpf.id_user,
      cpf.uuid_user,
      cpf.id_house,
      cpf.id_rent_flow,
      cpf.id_proposal,
      cpf.ts_credit_positive,
      COALESCE(rff.documentation_sent, FALSE) AS documentation_sent,
      COALESCE(rff.has_documentation_canceled, FALSE) AS has_documentation_canceled,
      rff.ts_documentation_sent
    FROM
      credit_positive_flows AS cpf
      LEFT JOIN rent_flow_flags AS rff ON cpf.uuid_user = rff.uuid_user
      AND cpf.id_rent_flow = rff.id_rent_flow
  ),
  enriched_flows AS (
    SELECT
      ef.id_event,
      ef.id_user,
      ef.uuid_user,
      ef.id_house,
      ef.id_rent_flow,
      ef.id_proposal,
      ef.ts_credit_positive AS ts_evaluation_positive,
      ef.ts_documentation_sent,
      ef.documentation_sent,
      COALESCE(ef.has_documentation_canceled, FALSE) = FALSE AS is_active_rent_flow,
      TRIM(us_ebdb.email) AS user_email,
      REPLACE(us_ebdb.main_phone, '+', '') AS user_phone,
      SPLIT_PART(us_ebdb.name, ' ', 1) AS user_first_name,
      hs.address,
      hs.number,
      EXISTS (
        SELECT
          1
        FROM
          datalake_copilot_service_clean.session AS session_cp
          INNER JOIN datalake_copilot_service_clean.message AS message_cp ON message_cp.id_session = session_cp.id
        WHERE
          TRY_CAST(session_cp.id_user AS BIGINT) = ef.id_user
          AND session_cp.ts_created >= ef.ts_credit_positive
          AND message_cp.channel = 'WHATSAPP_SONIA_CHAT'
      ) AS has_answered
    FROM
      eligible_flows AS ef
      INNER JOIN datalake_ebdb_clean.user AS us_ebdb ON ef.id_user = us_ebdb.id
      LEFT JOIN datalake_ebdb_clean.house AS hs ON ef.id_house = hs.id
  )
SELECT
  ef.id_event || '_' || ef.uuid_user AS pk_event_user,
  ef.id_event,
  ef.id_rent_flow,
  ef.id_user,
  ef.uuid_user,
  ef.id_proposal,
  'https://www.quintoandar.com.br/documentacao/'
    || CAST(ef.id_proposal AS VARCHAR)
    || '?source_platform=sonia&utm_source=sonia' AS documentation_url,
  ef.id_house,
  ef.is_active_rent_flow,
  ef.documentation_sent,
  ef.has_answered,
  ef.user_email,
  ef.user_phone,
  ef.user_first_name,
  CONCAT_WS(', ', ef.address, CAST(ef.number AS VARCHAR)) AS address_text,
  ABS(CRC32(TO_UTF8(ef.uuid_user))) % 100 AS binning_value,
  DATE_FORMAT(ef.ts_evaluation_positive, '%Y-%m-%d %T') AS ts_evaluation_positive,
  DATE_FORMAT(ef.ts_documentation_sent, '%Y-%m-%d %T') AS ts_documentation_sent
FROM
  enriched_flows AS ef
