SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    business_unit_id AS id_business_unit,
    user_id AS id_user,
    version,
    parent_member_profile_id AS id_parent_member_profile,
    profile,
    active AS is_active,
    business_unit_id_mod AS mod_id_business_unit,
    user_id_mod AS mod_id_user,
    profile_mod AS mod_profile,
    active_mod AS mod_active,
    parent_member_profile_id_mod AS mod_id_parent_member_profile,
    relationship_start_date_mod AS mod_dt_relationship_started, 
    relationship_start_date AS dt_relationship_started,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.member_profile_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
