-- ================================================================
-- Consórcio Blip WhatsApp messages (clean)
-- Grain: one row per id_message
-- Source: datalake_consorcio_raw.blip_messages
-- Window: raw ts_load >= {load_start_date} (insert-only merge on
-- id_message). MERGE requires a unique source key: collapse to one
-- row per id_message with ROW_NUMBER (no QUALIFY) after the lead
-- lookups, because those joins can fan out even when raw is unique.
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
--   3) Blip identity via tunnel
--   4) Blip identity via WhatsApp contact
-- Blip identity resolves through contact_property (contact identity flag
-- at 100%, so every new write lands there) and falls back to the frozen
-- lead_external_data bsp columns for conversations that predate it.
-- crm_id is not a contact_property key; it is read from
-- lead_external_data by the winning id_lead.
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
-- Latest lead per contact. A contact owns every lead the same person
-- produced (recapture creates a new lead, reusing the contact), so the
-- newest lead wins — the same tie-break the LED bridge applied when a
-- donated conversation id appeared on more than one lead.
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
-- Blip identity → lead, from both identity stores. contact_property is the
-- current source of truth (contact identity flag at 100%); the LED bsp
-- columns still carry the history written before it, and stay frozen from
-- now on. source_priority makes contact_property win a disagreement.
bsp_identity AS (
  SELECT
    property_kind,
    id_bsp_value,
    id_lead
  FROM (
    SELECT
      ranked_identity.property_kind,
      ranked_identity.id_bsp_value,
      ranked_identity.id_lead,
      ROW_NUMBER() OVER (
        PARTITION BY
          ranked_identity.property_kind,
          ranked_identity.id_bsp_value
        ORDER BY
          ranked_identity.source_priority,
          ranked_identity.id_lead DESC
      ) AS rn_identity
    FROM (
      SELECT
        contact_property.property_key AS property_kind,
        CASE
          WHEN INSTR(contact_property.property_value, '@') > 0
            THEN contact_property.property_value
          WHEN contact_property.property_key = 'BSP_CONVERSATION_ID'
            THEN CONCAT(contact_property.property_value, '@tunnel.msging.net')
          ELSE CONCAT(contact_property.property_value, '@wa.gw.msging.net')
        END AS id_bsp_value,
        latest_lead_by_contact.id_lead,
        1 AS source_priority
      FROM
        datalake_consorcio_clean.contact_property AS contact_property
      INNER JOIN
        latest_lead_by_contact
          ON latest_lead_by_contact.id_contact = contact_property.id_contact
          AND latest_lead_by_contact.rn = 1
      WHERE
        contact_property.property_key IN ('BSP_CONVERSATION_ID', 'BSP_CONTACT_ID')
        AND contact_property.property_value IS NOT NULL
        AND TRIM(contact_property.property_value) <> ''
      UNION ALL
      SELECT
        'BSP_CONVERSATION_ID' AS property_kind,
        CASE
          WHEN INSTR(lead_external.id_bsp_conversation, '@') > 0
            THEN lead_external.id_bsp_conversation
          ELSE CONCAT(lead_external.id_bsp_conversation, '@tunnel.msging.net')
        END AS id_bsp_value,
        lead_external.id_lead,
        2 AS source_priority
      FROM
        datalake_consorcio_clean.lead_external_data AS lead_external
      WHERE
        lead_external.id_bsp_conversation IS NOT NULL
        AND TRIM(lead_external.id_bsp_conversation) <> ''
      UNION ALL
      SELECT
        'BSP_CONTACT_ID' AS property_kind,
        CASE
          WHEN INSTR(lead_external.id_bsp_contact, '@') > 0
            THEN lead_external.id_bsp_contact
          ELSE CONCAT(lead_external.id_bsp_contact, '@wa.gw.msging.net')
        END AS id_bsp_value,
        lead_external.id_lead,
        2 AS source_priority
      FROM
        datalake_consorcio_clean.lead_external_data AS lead_external
      WHERE
        lead_external.id_bsp_contact IS NOT NULL
        AND TRIM(lead_external.id_bsp_contact) <> ''
    ) AS ranked_identity
  ) AS deduped_identity
  WHERE
    rn_identity = 1
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
),
enriched AS (
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
        THEN COALESCE(crm_tunnel.id_crm, normalized.id_crm)
      WHEN lead_contact.id_lead IS NOT NULL
        THEN COALESCE(crm_contact.id_crm, normalized.id_crm)
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
    bsp_identity AS lead_tunnel
      ON lead_tunnel.property_kind = 'BSP_CONVERSATION_ID'
      AND lead_tunnel.id_bsp_value = normalized.id_bsp
  LEFT JOIN
    bsp_identity AS lead_contact
      ON lead_contact.property_kind = 'BSP_CONTACT_ID'
      AND lead_contact.id_bsp_value = normalized.id_bsp_contact_normalized
  LEFT JOIN
    crm_by_lead AS crm_tunnel
      ON crm_tunnel.id_lead = lead_tunnel.id_lead
      AND crm_tunnel.rn = 1
  LEFT JOIN
    crm_by_lead AS crm_contact
      ON crm_contact.id_lead = lead_contact.id_lead
      AND crm_contact.rn = 1
),
ranked AS (
  SELECT
    enriched.id_lead,
    enriched.id_bsp,
    enriched.id_crm,
    enriched.id_message,
    enriched.host_name,
    enriched.role,
    enriched.content,
    enriched.ts_created,
    enriched.year,
    enriched.month,
    enriched.day,
    ROW_NUMBER() OVER (
      PARTITION BY enriched.id_message
      ORDER BY
        enriched.ts_created DESC NULLS LAST,
        enriched.id_lead DESC NULLS LAST
    ) AS rn_message
  FROM
    enriched
)
SELECT
  ranked.id_lead,
  ranked.id_bsp,
  ranked.id_crm,
  ranked.id_message,
  ranked.host_name,
  ranked.role,
  ranked.content,
  ranked.ts_created,
  ranked.year,
  ranked.month,
  ranked.day
FROM
  ranked
WHERE
  ranked.rn_message = 1
