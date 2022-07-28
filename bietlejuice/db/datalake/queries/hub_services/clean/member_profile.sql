SELECT
    id,
    business_unit_id AS id_business_unit,
    user_id AS id_user,
    version,
    parent_member_profile_id AS id_parent_member_profile,
    profile,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.member_profile
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
