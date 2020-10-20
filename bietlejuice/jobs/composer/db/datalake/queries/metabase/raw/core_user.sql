SELECT
    id,
    email,
    first_name,
    last_name,
    is_active,
    is_superuser,
    is_qbnewb,
    google_auth,
    ldap_auth,
    date_joined,
    last_login,
    updated_at,
    EXTRACT(year FROM updated_at)::INT AS year,
    EXTRACT(month FROM updated_at)::INT AS month,
    EXTRACT(day FROM updated_at)::INT AS day
FROM
    metabase."core_user"
WHERE 
    EXTRACT(year FROM updated_at) = {year}
    AND EXTRACT(month FROM updated_at) = {month}
    AND EXTRACT(day FROM updated_at) = {day}