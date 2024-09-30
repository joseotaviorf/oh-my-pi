SELECT
    id_ticket_audit AS sk_ticket_audit,
    id_ticket AS sk_ticket,
    id_author AS sk_author,
    id_event,
    type AS event_type,
    field_name,
    previous_value,
    value,
    event_via,
    sequence_number,
    table_version,
    is_public,
    dt_extracted,
    ts_batched,
    ts_received,
    ts_created,
    ts_created_local,
    ts_load
FROM
    datalake_velo_zendesk.ticket_audits
