SELECT
    id,
    company_id AS id_company,
    revenue_share_uuid AS uuid_revenue_share,
    commission,
    demand_fee,
    supply_fee,
    platform_fee,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    company_id_mod AS mod_id_company,
    revenue_share_uuid_mod AS mod_uuid_revenue_share,
    commission_mod AS mod_commission,
    demand_fee_mod AS mod_demand_fee,
    supply_fee_mod AS mod_supply_fee,
    platform_fee_mod AS mod_platform_fee,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.revenue_share_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}