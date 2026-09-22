-- Fan-out per ticket. vendor_natural_key is the parent id_ticket_tic (cursor-resolved,
-- not the row's own id_ticket_tic) pipe id_historico_tih, because history ids are not
-- unique across tickets. Join id_ticket_tic back to benvi_superlogica_ticket.
-- id_ticket_tic_row is the row's own copy, which the vendor leaves empty on some rows;
-- the extractor skips the row only when it is present and disagrees with the parent.
-- PII: st_contato_tih is a contact name and st_historico_tih is free text written by
-- the operator or the requester. Both are projected; Trino column-level ACL is the
-- access control, not omission here.
SELECT
    id,
    vendor_natural_key AS vendor_natural_key,
    split(vendor_natural_key, '\\\\|')[0] AS id_ticket_tic,
    split(vendor_natural_key, '\\\\|')[1] AS id_historico_tih,
    get_json_object(CAST(payload AS STRING), '$.id_ticket_tic') AS id_ticket_tic_row,
    get_json_object(CAST(payload AS STRING), '$.id_solicitante_tic') AS id_solicitante_tic,
    get_json_object(CAST(payload AS STRING), '$.id_responsavel_tic') AS id_responsavel_tic,
    get_json_object(CAST(payload AS STRING), '$.id_contato_tih') AS id_contato_tih,
    get_json_object(CAST(payload AS STRING), '$.st_contato_tih') AS contato_tih,
    get_json_object(CAST(payload AS STRING), '$.st_historico_tih') AS historico_tih,
    CAST(get_json_object(CAST(payload AS STRING), '$.fl_tipocontato_tih') AS INT) AS fl_tipocontato_tih,
    CAST(get_json_object(CAST(payload AS STRING), '$.fl_interno_tih') AS INT) AS fl_interno_tih,
    TO_DATE(get_json_object(CAST(payload AS STRING), '$.dt_historico_tih')) AS dt_historico_tih,
    synced_at AS ts_synced
FROM
    datalake_benvi_manager_raw.lake_mirror
WHERE
    resource_code = 'TICKET_HISTORY'
