SELECT
    id,
    profile_id AS id_profile,
    person_uuid AS uuid_person,
    company_product_product_id AS id_product,
    company_product_company_id AS id_company,
    version,
    status,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    profile_id_mod AS mod_id_profile,
    person_uuid_mod AS mod_uuid_person,
    status_mod AS mod_status,
    company_product_product_id_mod AS mod_id_product,
    company_product_company_id_mod AS mod_id_company,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_company_raw.member_profile_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
