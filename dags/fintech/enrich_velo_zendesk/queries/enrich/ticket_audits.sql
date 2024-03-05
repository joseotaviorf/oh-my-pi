WITH
filtered_events AS (
    SELECT
        id_ticket_audit,
        EXPLODE(SPLIT(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(events, '(?!)', ''), 'id:', ''), ',value', ''), '[', ''), ']', ''), '{', ''), '},')) AS events
    FROM
        datalake_velo_zendesk_clean.ticket_audits),
filtered_body AS (
    SELECT DISTINCT
        id_ticket_audit,
        SPLIT(events, '":')[0] AS id_events,
        SPLIT(events, '":')[1] AS events_value
    FROM
        filtered_events AS
    WHERE SPLIT(events, '":')[0] = '"body')

SELECT
    ta.id_ticket_audit,
    ta.id_ticket,
    ta.id_author,
    ta.event_via,
    REPLACE(SPLIT(fb.events_value, '","')[0],'"','') AS event_body,
    ta.sequence_number,
    ta.table_version,
    ta.dt_extracted,
    ta.ts_batched,
    ta.ts_received,
    ta.ts_created,
    ta.ts_load,
    year,
    month,
    day
FROM
    datalake_velo_zendesk_clean.ticket_audits ta
LEFT JOIN
    filtered_body fb
        ON fb.id = ta.id
