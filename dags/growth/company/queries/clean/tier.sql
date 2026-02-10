SELECT
    id,
    tier_uuid AS uuid_tier,
    tier_name,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.tier