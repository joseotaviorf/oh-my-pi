SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    version,
    name AS hub_name,
    business_context,
    sdr_type,
    negotiation_type,
    lead_types,
    name_mod AS mod_hub_name,
    business_context_mod AS mod_business_context,
    sdr_type_mod AS mod_sdr_type,
    negotiation_type_mod AS mod_negotiation_type,
    lead_type_mod AS mod_lead_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.business_unit_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}