SELECT
    id,
    house_id AS id_house,
    visitor_id AS id_visitor,
    business_unit_id AS id_business_unit,
    version,
    message,
    business_context,
    lead_type,
    lead_status,
    cancellation AS is_cancellation,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.lead
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}