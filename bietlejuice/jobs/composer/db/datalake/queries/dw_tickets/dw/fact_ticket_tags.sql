SELECT
    CAST(tf.id_ticket AS BIGINT) AS sk_ticket,
    tf_tag AS ticket_tag,
    tf.ts_updated,
    NOW() AS ts_load
FROM
    datalake_zendesk_tickets_clean.tickets tf
LATERAL VIEW
    EXPLODE(SPLIT(tf.tags,',')) AS tf_tag
