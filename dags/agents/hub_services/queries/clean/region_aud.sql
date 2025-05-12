SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    version,
    name AS region_name,
    name_mod AS mod_region_name,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.region_aud
