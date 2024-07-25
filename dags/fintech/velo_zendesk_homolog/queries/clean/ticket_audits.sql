SELECT
    id AS id_ticket_audit,
    ticket_id AS id_ticket,
    author_id AS id_author,
    CAST(GET_JSON_OBJECT(via, '$.channel') AS STRING) AS event_via,
    events,
    _sdc_sequence AS sequence_number,
    _sdc_table_version AS table_version,
    dt AS dt_extracted,
    _sdc_batched_at AS ts_batched,
    _sdc_received_at AS ts_received,
    created_at AS ts_created,
    NOW() AS ts_load,
    YEAR(CAST(dt AS DATE)) AS year,
    MONTH(CAST(dt AS DATE)) AS month,
    DAY(CAST(dt AS DATE)) AS day
FROM
    datalake_velo_zendesk_homolog_raw.ticket_audits
WHERE
    dt = DATE('{year}-{month}-{day}')
