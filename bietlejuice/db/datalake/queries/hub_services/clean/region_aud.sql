SELECT
    id,
    business_unit_id AS id_business_unit,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    version,
    name AS region_name,
    name_mod AS mod_region_name,
    business_unit_id_mod AS mod_id_business_unit,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.region_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}