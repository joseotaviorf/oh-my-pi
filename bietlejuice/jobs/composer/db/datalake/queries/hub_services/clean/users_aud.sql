SELECT
    id,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    version,
    external_id AS id_external,
    name AS hub_name,
    email,
    phone_number,
    email_mod AS mod_email,
    name_mod AS mod_name,
    phone_number_mod AS mod_phone_number,
    external_id_mod AS mod_id_external,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.users_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
