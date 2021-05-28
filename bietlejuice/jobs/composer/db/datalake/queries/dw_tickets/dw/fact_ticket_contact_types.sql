SELECT
    CAST(tct.id_ticket AS BIGINT) AS sk_ticket,
    COALESCE(CAST(DATE_FORMAT(tct.ts_updated, 'yMMdd') AS INTEGER), -1) AS sk_updated,
    tct.contact_type_tag,
    client_taxonomy,
    category_taxonomy,
    CAST(has_valid_prefix AS BOOLEAN) AS is_contact_type_taxonomy,
    tct.ts_updated,
    NOW() AS ts_load
FROM
    datalake_zendesk_tickets.ticket_contact_types tct
