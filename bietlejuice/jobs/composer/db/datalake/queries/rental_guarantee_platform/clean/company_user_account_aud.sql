SELECT
    id,
    user_account_id AS id_user_account,
    profile_account_id AS id_profile_account,
    company_id AS id_company,
    active AS is_active,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    user_account_id_mod AS mod_id_user_account,
    profile_account_id_mod AS mod_id_profile_account,
    active_mod AS mod_is_active,
    company_id_mod AS mod_id_company,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.company_user_account_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}