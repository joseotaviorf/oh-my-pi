SELECT
    id,
    email,
    first_name,
    last_name,
    is_active,
    is_superuser,
    is_qbnewb,
    google_auth as has_google_auth,
    ldap_auth as has_ldap_auth,
    date_joined as ts_joined,
    last_login as ts_last_login,
    updated_at as ts_updated,
    year,
    month,
    day
FROM
    datalake_metabase_raw.core_user
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}