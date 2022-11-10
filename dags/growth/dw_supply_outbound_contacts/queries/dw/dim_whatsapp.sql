SELECT
    id_outbound_contact AS sk_outbound_contact,
    ELEMENT_AT(contact_extra_info, "message_template") AS message_template,
    ELEMENT_AT(contact_extra_info, "tags") AS tags, 
    ELEMENT_AT(contact_extra_info,  "message_status") AS message_status,
    CAST(ELEMENT_AT(contact_extra_info, "whatsapp_opt_in") AS BOOLEAN) AS has_opted_in,
    NOW() AS ts_load
FROM
    datalake_supply_outbound_flows.supply_outbound_contacts
WHERE
    contact_channel = 'WHATSAPP'