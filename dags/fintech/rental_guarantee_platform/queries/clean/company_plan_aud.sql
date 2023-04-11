SELECT
    id,
    plan_id AS id_plan,
    company_id AS id_company,
    pricing,
    coverage,
    damage,
    commission,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    active AS is_active,
    company_id_mod AS mod_id_company,
    pricing_mod AS mod_princing,
    coverage_mod AS mod_coverage,
    damage_mod AS mod_damage,
    commission_mod AS mod_comission,
    plan_id_mod AS mod_id_plan,
    active_mod AS mod_is_active,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.company_plan_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
