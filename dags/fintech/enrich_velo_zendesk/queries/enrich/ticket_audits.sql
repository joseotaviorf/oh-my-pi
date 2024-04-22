WITH base_ticket_audits AS (
    SELECT
        id_ticket_audit,
        id_ticket,
        id_author,
        event_via,
        EXPLODE(FROM_JSON(events, 'array<struct<id: string, type: string, field_name: string, previous_value: string, value: string>>')) AS parsed_events,
        sequence_number,
        table_version,
        dt_extracted,
        ts_batched,
        ts_received,
        ts_created,
        ts_load,
        year,
        month,
        day
    FROM datalake_velo_zendesk_clean.ticket_audits
)

SELECT
  ta.id_ticket_audit,
  ta.id_ticket,
  ta.id_author,
  ta.event_via,
  ta.sequence_number,
  ta.table_version,
  ta.parsed_events.id AS id_event,
  ta.parsed_events.type AS type,
  ta.parsed_events.field_name AS field_name,
  ta.parsed_events.previous_value AS previous_value,
  ta.parsed_events.value AS value,
  ta.dt_extracted,
  ta.ts_batched,
  ta.ts_received,
  ta.ts_created,
  ta.ts_load,
  ta.year,
  ta.month,
  ta.day
FROM
   base_ticket_audits ta
