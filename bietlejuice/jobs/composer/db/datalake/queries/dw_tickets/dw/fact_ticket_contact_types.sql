SELECT
    tct.id_ticket AS sk_ticket,
    COALESCE(CAST(DATE_FORMAT(tct.ts_updated, '%Y%m%d') AS INTEGER), -1) AS sk_updated,
    tct.contact_type_tag,
    client_taxonomy,
    category_taxonomy,
    has_valid_prefix AS is_contact_type_taxonomy,
    tct.ts_updated,
    NOW() AS ts_load
FROM
    datalake_zendesk_tickets.ticket_contact_types tct
