SELECT
    id,
    house_id AS id_house,
    visitor_id AS id_visitor,
    business_unit_id AS id_business_unit,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    version,
    message,
    business_context,
    lead_type,
    lead_status,
    cancellation AS is_cancellation,
    is_secretariat,
    house_id_mod AS mod_id_house,
    cancellation_mod AS mod_is_cancellation,
    is_secretariat_mod AS mod_is_secretariat,
    visitor_id_mod AS mod_id_visitor,
    sent_mod AS mod_sent,
    message_mod AS mod_message,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.lead_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}