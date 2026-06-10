WITH updated_business_unit_region AS (
    SELECT DISTINCT 
        id_business_unit
    FROM 
        datalake_hub_services_clean.business_unit_region_aud
    WHERE 
        DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    aud.id AS id_business_unit_region,
    bu.id AS id_business_unit,
    aud.id_region,
    bu.hub_name,
    r.region_code,
    r.city_group,
    r.city_name,
    r.short_region_name,
    bu.sdr_type,
    bu.lead_types,
    bu.negotiation_type,
    COALESCE(aud.business_context, bu.business_context) AS business_context,
    bu.operational_context,
    ROW_NUMBER() OVER(PARTITION BY bu.id ORDER BY aud.ts_updated DESC) = 1 AS is_last_region_associated,
    aud.ts_created AS ts_business_unit_region_started,
    aud_end.ts_created AS ts_business_unit_region_ended,
    aud.ts_updated AS ts_business_unit_region_updated,
    bu.ts_created AS ts_business_unit_created,
    bu.ts_updated AS ts_business_unit_updated,
    bu.year,
    bu.month,
    bu.day
FROM
    datalake_hub_services_clean.business_unit_region_aud AS aud
JOIN
    updated_business_unit_region AS updated
        ON updated.id_business_unit = aud.id_business_unit
JOIN
    datalake_hub_services_clean.business_unit AS bu
        ON bu.id = aud.id_business_unit
LEFT JOIN
    datalake_hub_services_clean.business_unit_region_aud AS aud_end
        ON aud_end.rev = aud.rev_end
        AND aud_end.id = aud.id
LEFT JOIN 
    datalake_region.region AS r
        ON aud.id_region = CAST(r.id AS INT)
WHERE
    aud.rev_type <> 2