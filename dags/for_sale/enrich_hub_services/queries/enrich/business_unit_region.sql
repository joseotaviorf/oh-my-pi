WITH hub_regions_aud AS (
    SELECT
        bur_aud.id,
        bur_aud.id_business_unit,
        bur_aud.id_region,
        bur_aud.rev,
        bur_aud.rev_end,
        bur_aud.rev_type,
        bur_aud.ts_created
    FROM
        datalake_hub_services_clean.business_unit_region_aud AS bur_aud
),
regions_coverage_dates AS (
    SELECT
        id_business_unit,
        id_region,
        rev_type,
        ts_created AS ts_start,
        LEAD(ts_created) OVER (PARTITION BY id ORDER BY ts_created) AS ts_end
    FROM
        hub_regions_aud
),
last_business_unit_info AS (
    SELECT
        id AS id_business_unit,
        hub_name,
        sdr_type AS business_model,
        lead_types,
        negotiation_type
    FROM
        datalake_hub_services_clean.business_unit
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_business_unit ORDER BY version DESC) = 1
)
SELECT
    rcd.id_business_unit,
    rcd.id_region,
    l_hub.hub_name,
    l_hub.business_model,
    l_hub.lead_types,
    l_hub.negotiation_type,
    rcd.ts_start AS ts_start_coverage,
    rcd.ts_end AS ts_end_coverage
FROM
    regions_coverage_dates AS rcd
LEFT JOIN
    last_business_unit_info AS l_hub
        ON l_hub.id_business_unit = rcd.id_business_unit
WHERE
    rcd.rev_type != 2
