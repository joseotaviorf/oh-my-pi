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
),
hub_services_cte AS (
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
),
historical_data AS (
    SELECT
        CAST(NULL AS INT) AS id_business_unit,
        bur_g.id_region,
        bur_g.business_unit AS hub_name,
        bur_g.business_model,
        ARRAY() AS lead_types,
        CAST(NULL AS STRING) AS negotiation_type,
        TIMESTAMP(bur_g.dt_start) AS ts_start_coverage,
        LEAST(TIMESTAMP(NULLIF(bur_g.dt_end, "2022-05-23T17:25:17")), TO_TIMESTAMP("2022-05-23 17:25:17", "yyyy-MM-dd HH:mm:ss")) AS ts_end_coverage
    FROM
        datalake_gsheets_clean.business_unit_region AS bur_g
    WHERE
        bur_g.dt_start <= "2022-05-23T17:25:17"
)
SELECT
    id_business_unit,
    id_region,
    hub_name,
    business_model,
    lead_types,
    negotiation_type,
    ts_start_coverage,
    ts_end_coverage
FROM
    hub_services_cte
UNION ALL
SELECT
    id_business_unit,
    id_region,
    hub_name,
    business_model,
    lead_types,
    negotiation_type,
    ts_start_coverage,
    ts_end_coverage
FROM
    historical_data
