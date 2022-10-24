SELECT
    id,
    user_account_id AS id_user_account,
    profile_account_id AS id_profile_account,
    company_id AS id_company,
    version,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.company_user_account
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}