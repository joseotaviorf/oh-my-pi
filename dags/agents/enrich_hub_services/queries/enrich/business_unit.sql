SELECT
    bu.id AS id_business_unit,
    bur.id_region,
    bu.hub_name,
    r.region_code,
    r.city_group,
    r.city_name,
    r.short_region_name,
    bu.sdr_type,
    bu.lead_types,
    bu.negotiation_type,
    bu.business_context,
    bu.operational_context,
    ROW_NUMBER() OVER(PARTITION BY bu.id ORDER BY bur.ts_updated DESC) = 1 AS is_last_region_associated,
    bur.ts_created AS ts_region_association_created,
    bur.ts_updated AS ts_region_association_updated,
    bu.ts_created AS ts_business_unit_created,
    bu.ts_updated AS ts_business_unit_updated,
    bu.year,
    bu.month,
    bu.day
FROM
    datalake_hub_services_clean.business_unit AS bu
LEFT JOIN 
    datalake_hub_services_clean.business_unit_region AS bur
        ON bu.id = bur.id_business_unit
LEFT JOIN 
    datalake_region.region AS r
        ON bur.id_region = CAST(r.id AS INT)
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY bu.id, bu.business_context, bur.id_region ORDER BY bur.ts_updated DESC) = 1