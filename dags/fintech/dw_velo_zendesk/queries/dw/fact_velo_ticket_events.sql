SELECT
    id_ticket_audit AS sk_ticket_audit,
    id_ticket AS sk_ticket,
    id_author AS sk_author,
    event_via,
    event_body,
    sequence_number,
    table_version,
    dt_extracted,
    ts_batched,
    ts_received,
    ts_created,
    ts_load
FROM
    datalake_velo_zendesk.ticket_audits
