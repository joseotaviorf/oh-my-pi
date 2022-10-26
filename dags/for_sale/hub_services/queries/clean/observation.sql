SELECT
    id,
    visitor_id AS id_visitor,
    version,
    created_by,
    creator_name,
    value,
    creator_email,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.observation
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
