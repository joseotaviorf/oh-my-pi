-- ================================================================
-- Chat messages façade for Consórcio conversational analytics
-- Grain: one row per Copilot message (id_message)
-- Scoped to Conrado only (Langfuse host tag); widen later if needed
-- Incremental merge on id_message over {load_start_date}..{load_end_date}
-- (scheduled default: last 30 days; override conf for historical backfill)
-- ================================================================
WITH messages_in_window AS (
  SELECT
    copilot_message.id AS id_message,
    copilot_message.id_session,
    copilot_message.role,
    copilot_message.content,
    copilot_message.ts_created,
    copilot_session.id_external AS id_langfuse_session
  FROM
    datalake_copilot_service_clean.message AS copilot_message
  INNER JOIN
    datalake_copilot_service_clean.session AS copilot_session
      ON copilot_session.id = copilot_message.id_session
  WHERE
    copilot_message.ts_created >= DATE('{load_start_date}')
    AND copilot_message.ts_created < DATE_ADD(DATE('{load_end_date}'), 1)
    AND copilot_session.id_external IS NOT NULL
),
sessions_in_window AS (
  SELECT DISTINCT
    messages_in_window.id_langfuse_session
  FROM
    messages_in_window
),
-- Resolve Conrado host + BSP from Langfuse for sessions with in-window messages.
-- Traces use the same load window as messages.
session_host AS (
  SELECT
    langfuse_traces.id_session AS id_langfuse_session,
    LOWER(MAX(langfuse_traces.tags[0])) AS host_name,
    -- Blip conversation id (uuid@tunnel.msging.net), not contact
    MAX(langfuse_traces.id_user) AS id_bsp
  FROM
    datalake_langfuse_clean.traces AS langfuse_traces
  INNER JOIN
    sessions_in_window
      ON sessions_in_window.id_langfuse_session = langfuse_traces.id_session
  WHERE
    langfuse_traces.ts_created >= DATE('{load_start_date}')
    AND langfuse_traces.ts_created < DATE_ADD(DATE('{load_end_date}'), 1)
    AND langfuse_traces.id_session IS NOT NULL
    AND langfuse_traces.tags IS NOT NULL
    AND SIZE(langfuse_traces.tags) > 0
    AND langfuse_traces.tags[0] IS NOT NULL
    AND LOWER(langfuse_traces.tags[0]) = 'conrado'
  GROUP BY
    langfuse_traces.id_session
),
-- Langfuse traces.id_user is the Blip conversation id; id_bsp_contact
-- matched 0%, so only the tunnel key is read here.
-- A contact owns every lead the same person produced (recapture reuses the
-- contact), so the newest lead wins — the same tie-break the LED bridge
-- applied when a donated conversation id appeared on more than one lead.
latest_lead_by_contact AS (
  SELECT
    consorcio_lead.id_contact,
    consorcio_lead.id AS id_lead,
    ROW_NUMBER() OVER (
      PARTITION BY consorcio_lead.id_contact
      ORDER BY
        consorcio_lead.ts_updated DESC NULLS LAST,
        consorcio_lead.ts_created DESC,
        consorcio_lead.id DESC
    ) AS rn
  FROM
    datalake_consorcio_clean.lead AS consorcio_lead
  WHERE
    consorcio_lead.id_contact IS NOT NULL
),
-- crm_id is not a contact_property key: consorcio-api keeps writing it to
-- lead_external_data, so the deal id is always looked up by lead.
crm_by_lead AS (
  SELECT
    lead_external.id_lead,
    lead_external.id_crm,
    ROW_NUMBER() OVER (
      PARTITION BY lead_external.id_lead
      ORDER BY
        lead_external.ts_updated DESC NULLS LAST,
        lead_external.ts_created DESC
    ) AS rn
  FROM
    datalake_consorcio_clean.lead_external_data AS lead_external
  WHERE
    lead_external.id_crm IS NOT NULL
    AND TRIM(lead_external.id_crm) <> ''
),
-- Tunnel → lead, from both identity stores. contact_property is the current
-- source of truth (contact identity flag at 100%); the LED bsp columns still
-- carry the history written before it, and stay frozen from now on.
-- source_priority makes contact_property win a disagreement.
lead_by_bsp AS (
  SELECT
    id_bsp,
    id_lead,
    id_crm
  FROM (
    SELECT
      ranked_identity.id_bsp,
      ranked_identity.id_lead,
      crm_by_lead.id_crm,
      ROW_NUMBER() OVER (
        PARTITION BY ranked_identity.id_bsp
        ORDER BY
          ranked_identity.source_priority,
          ranked_identity.id_lead DESC
      ) AS rn_identity
    FROM (
      SELECT
        CASE
          WHEN INSTR(contact_property.property_value, '@') > 0
            THEN contact_property.property_value
          ELSE CONCAT(contact_property.property_value, '@tunnel.msging.net')
        END AS id_bsp,
        latest_lead_by_contact.id_lead,
        1 AS source_priority
      FROM
        datalake_consorcio_clean.contact_property AS contact_property
      INNER JOIN
        latest_lead_by_contact
          ON latest_lead_by_contact.id_contact = contact_property.id_contact
          AND latest_lead_by_contact.rn = 1
      WHERE
        contact_property.property_key = 'BSP_CONVERSATION_ID'
        AND contact_property.property_value IS NOT NULL
        AND TRIM(contact_property.property_value) <> ''
      UNION ALL
      SELECT
        CASE
          WHEN INSTR(lead_external.id_bsp_conversation, '@') > 0
            THEN lead_external.id_bsp_conversation
          ELSE CONCAT(lead_external.id_bsp_conversation, '@tunnel.msging.net')
        END AS id_bsp,
        lead_external.id_lead,
        2 AS source_priority
      FROM
        datalake_consorcio_clean.lead_external_data AS lead_external
      WHERE
        lead_external.id_bsp_conversation IS NOT NULL
        AND TRIM(lead_external.id_bsp_conversation) <> ''
    ) AS ranked_identity
    LEFT JOIN
      crm_by_lead
        ON crm_by_lead.id_lead = ranked_identity.id_lead
        AND crm_by_lead.rn = 1
  ) AS deduped_identity
  WHERE
    rn_identity = 1
)
SELECT
  lead_bridge.id_lead,
  session_host.id_bsp,
  lead_bridge.id_crm,
  messages_in_window.id_message,
  messages_in_window.id_session,
  session_host.host_name,
  LOWER(messages_in_window.role) AS role,
  messages_in_window.content,
  messages_in_window.ts_created,
  YEAR(messages_in_window.ts_created) AS year,
  MONTH(messages_in_window.ts_created) AS month,
  DAY(messages_in_window.ts_created) AS day
FROM
  messages_in_window
INNER JOIN
  session_host
    ON session_host.id_langfuse_session = messages_in_window.id_langfuse_session
LEFT JOIN
  lead_by_bsp AS lead_bridge
    ON lead_bridge.id_bsp = session_host.id_bsp
