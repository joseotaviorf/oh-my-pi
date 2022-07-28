SELECT
    id,
    version,
    name AS hub_name,
    business_context,
    sdr_type,
    negotiation_type,
    lead_types,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.business_unit
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}