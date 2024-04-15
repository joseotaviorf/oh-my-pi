SELECT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
    REPLACE(REPLACE(REPLACE(tf_tag, '[', ''), ']', ''), '"', '') AS ticket_tag,
    ts_updated,
    NOW() AS ts_load
FROM
    datalake_zendesk.tickets_current
LATERAL VIEW
    EXPLODE(SPLIT(tags,',')) AS tf_tag
