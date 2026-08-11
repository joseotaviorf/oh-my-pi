-- ================================================================
-- Consórcio Blip WhatsApp messages (clean)
-- Grain: one row per id_message
-- Source: datalake_consorcio_raw.blip_messages
-- Window: raw ts_load >= {load_start_date} (insert-only merge on
-- id_message keeps re-runs idempotent)
-- Schema aligned with datalake_consorcio.chat_messages:
--   id_lead, id_bsp, id_crm, id_message, host_name, role, content,
--   ts_created, year, month, day
-- (no id_session — Blip JSONL has no Copilot session)
-- id_bsp = Blip tunnel identity (same semantic as chat_messages.id_bsp);
-- WhatsApp contact used only for lead enrichment, not emitted.
-- Producer raw id_lead is mixed: numeric lead.id OR lead.uuid.
-- id_lead resolution (paired with id_crm):
--   1) numeric producer id_lead
--   2) producer UUID → lead.id
--   3) lead_external via tunnel
--   4) lead_external via WhatsApp contact
-- ================================================================
WITH raw_in_window AS (
  SELECT
    raw_msg.id_message,
    NULLIF(TRIM(raw_msg.id_lead), '') AS producer_id_lead,
    NULLIF(TRIM(raw_msg.id_crm), '') AS id_crm,
    NULLIF(TRIM(raw_msg.id_tunnel), '') AS id_tunnel,
    NULLIF(TRIM(raw_msg.whatsapp_identity), '') AS whatsapp_identity,
    NULLIF(TRIM(raw_msg.host_name), '') AS host_name,
    LOWER(NULLIF(TRIM(raw_msg.role), '')) AS role,
    NULLIF(TRIM(raw_msg.content), '') AS content,
    raw_msg.ts_created
  FROM
    datalake_consorcio_raw.blip_messages AS raw_msg
  WHERE
    raw_msg.ts_load >= TIMESTAMP('{load_start_date}')
    AND raw_msg.id_message IS NOT NULL
    AND TRIM(raw_msg.id_message) <> ''
),
normalized AS (
  SELECT
    raw_in_window.id_message,
    raw_in_window.producer_id_lead,
    TRY_CAST(raw_in_window.producer_id_lead AS BIGINT) AS producer_id_lead_numeric,
    raw_in_window.id_crm,
    raw_in_window.host_name,
    raw_in_window.role,
    raw_in_window.content,
    raw_in_window.ts_created,
    CASE
      WHEN raw_in_window.id_tunnel IS NULL THEN NULL
      WHEN INSTR(raw_in_window.id_tunnel, '@') > 0 THEN raw_in_window.id_tunnel
      ELSE CONCAT(raw_in_window.id_tunnel, '@tunnel.msging.net')
    END AS id_bsp,
    CASE
      WHEN raw_in_window.whatsapp_identity IS NULL THEN NULL
      WHEN INSTR(raw_in_window.whatsapp_identity, '@') > 0
        THEN raw_in_window.whatsapp_identity
      ELSE CONCAT(raw_in_window.whatsapp_identity, '@wa.gw.msging.net')
    END AS id_bsp_contact_normalized
  FROM
    raw_in_window
),
lead_by_tunnel AS (
  SELECT
    CASE
      WHEN INSTR(lead_external.id_bsp_conversation, '@') > 0
        THEN lead_external.id_bsp_conversation
      ELSE CONCAT(lead_external.id_bsp_conversation, '@tunnel.msging.net')
    END AS id_bsp,
    lead_external.id_lead,
    lead_external.id_crm,
    ROW_NUMBER() OVER (
      PARTITION BY
        CASE
          WHEN INSTR(lead_external.id_bsp_conversation, '@') > 0
            THEN lead_external.id_bsp_conversation
          ELSE CONCAT(lead_external.id_bsp_conversation, '@tunnel.msging.net')
        END
      ORDER BY
        lead_external.ts_updated DESC NULLS LAST,
        lead_external.ts_created DESC
    ) AS rn
  FROM
    datalake_consorcio_clean.lead_external_data AS lead_external
  WHERE
    lead_external.id_bsp_conversation IS NOT NULL
    AND TRIM(lead_external.id_bsp_conversation) <> ''
),
lead_by_contact AS (
  SELECT
    CASE
      WHEN INSTR(lead_external.id_bsp_contact, '@') > 0
        THEN lead_external.id_bsp_contact
      ELSE CONCAT(lead_external.id_bsp_contact, '@wa.gw.msging.net')
    END AS id_bsp_contact_normalized,
    lead_external.id_lead,
    lead_external.id_crm,
    ROW_NUMBER() OVER (
      PARTITION BY
        CASE
          WHEN INSTR(lead_external.id_bsp_contact, '@') > 0
            THEN lead_external.id_bsp_contact
          ELSE CONCAT(lead_external.id_bsp_contact, '@wa.gw.msging.net')
        END
      ORDER BY
        lead_external.ts_updated DESC NULLS LAST,
        lead_external.ts_created DESC
    ) AS rn
  FROM
    datalake_consorcio_clean.lead_external_data AS lead_external
  WHERE
    lead_external.id_bsp_contact IS NOT NULL
    AND TRIM(lead_external.id_bsp_contact) <> ''
),
lead_by_uuid AS (
  SELECT
    lead.uuid AS uuid_lead,
    lead.id AS id_lead,
    ROW_NUMBER() OVER (
      PARTITION BY lead.uuid
      ORDER BY
        lead.ts_updated DESC NULLS LAST,
        lead.ts_created DESC,
        lead.id DESC
    ) AS rn
  FROM
    datalake_consorcio_clean.lead AS lead
  WHERE
    lead.uuid IS NOT NULL
    AND TRIM(CAST(lead.uuid AS STRING)) <> ''
)
SELECT
  CASE
    WHEN normalized.producer_id_lead_numeric IS NOT NULL
      THEN normalized.producer_id_lead_numeric
    WHEN lead_uuid.id_lead IS NOT NULL THEN lead_uuid.id_lead
    WHEN lead_tunnel.id_lead IS NOT NULL THEN lead_tunnel.id_lead
    WHEN lead_contact.id_lead IS NOT NULL THEN lead_contact.id_lead
    ELSE NULL
  END AS id_lead,
  normalized.id_bsp,
  CASE
    WHEN normalized.producer_id_lead_numeric IS NOT NULL
      OR lead_uuid.id_lead IS NOT NULL
      THEN normalized.id_crm
    WHEN lead_tunnel.id_lead IS NOT NULL
      THEN COALESCE(CAST(lead_tunnel.id_crm AS STRING), normalized.id_crm)
    WHEN lead_contact.id_lead IS NOT NULL
      THEN COALESCE(CAST(lead_contact.id_crm AS STRING), normalized.id_crm)
    ELSE normalized.id_crm
  END AS id_crm,
  normalized.id_message,
  normalized.host_name,
  normalized.role,
  normalized.content,
  normalized.ts_created,
  YEAR(normalized.ts_created) AS year,
  MONTH(normalized.ts_created) AS month,
  DAY(normalized.ts_created) AS day
FROM
  normalized
LEFT JOIN
  lead_by_uuid AS lead_uuid
    ON normalized.producer_id_lead_numeric IS NULL
    AND lead_uuid.uuid_lead = normalized.producer_id_lead
    AND lead_uuid.rn = 1
LEFT JOIN
  lead_by_tunnel AS lead_tunnel
    ON lead_tunnel.id_bsp = normalized.id_bsp
    AND lead_tunnel.rn = 1
LEFT JOIN
  lead_by_contact AS lead_contact
    ON lead_contact.id_bsp_contact_normalized = normalized.id_bsp_contact_normalized
    AND lead_contact.rn = 1
