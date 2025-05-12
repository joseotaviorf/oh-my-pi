SELECT 
    id,
    business_unit_id AS id_business_unit,
    region_id AS id_region,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    business_context,
    version,
    business_unit_id_mod AS mod_id_business_unit,
    region_id_mod AS mod_id_region,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.business_unit_region_aud
