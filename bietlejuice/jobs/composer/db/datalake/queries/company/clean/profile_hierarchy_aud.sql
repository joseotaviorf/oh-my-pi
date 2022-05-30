SELECT
    id,
    profile_id AS id_profile,
    product_id AS id_product,
    version,
    position_number,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    profile_id_mod AS mod_id_profile,
    position_number_mod AS mod_position_number,
    subsidiary_product_id_mod AS mod_id_subsidiary_product,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_company_raw.profile_hierarchy_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
