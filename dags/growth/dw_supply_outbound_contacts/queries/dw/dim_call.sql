SELECT
    id_outbound_contact AS sk_outbound_contact,
    ELEMENT_AT(contact_extra_info, "call_output") AS call_output, 
    ELEMENT_AT(contact_extra_info, "round_number") AS round_number,
    ELEMENT_AT(contact_extra_info, "round_max_tries") AS round_max_tries,
    ELEMENT_AT(contact_extra_info,  "call_number_in_round") AS call_number_in_round,
    ELEMENT_AT(contact_extra_info, "ts_call_round_started") AS ts_call_round_started,
    NOW() AS ts_load
FROM
    datalake_supply_outbound_flows.supply_outbound_contacts
WHERE
    contact_channel = 'PHONE'