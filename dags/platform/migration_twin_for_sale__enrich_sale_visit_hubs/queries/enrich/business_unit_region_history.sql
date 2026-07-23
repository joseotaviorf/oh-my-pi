SELECT
    bu.id_business_unit_region,
    bu.id_business_unit,
    bu.id_region,
    bu.business_context,
    bu.hub_name,
    bu.sdr_type AS business_model,
    bu.lead_types,
    bu.negotiation_type,
    bu.ts_business_unit_region_started AS ts_start_coverage,
    bu.ts_business_unit_region_ended AS ts_end_coverage
FROM
    datalake_hub_services.business_unit AS bu

UNION ALL

SELECT
    -1 AS id_business_unit_region,
    -1 AS id_business_unit,
    bur.id_region,
    NULL AS business_context,
    bur.business_unit AS hub_name,
    bur.business_model,
    NULL AS lead_types,
    NULL AS negotiation_type,
    TIMESTAMP(bur.dt_start) AS ts_start_coverage,
    LEAST(TIMESTAMP(NULLIF(bur.dt_end, "2022-05-23T17:25:17")), TO_TIMESTAMP("2022-05-23 17:25:17", "yyyy-MM-dd HH:mm:ss")) AS ts_end_coverage
FROM
    datalake_gsheets_clean.business_unit_region AS bur
WHERE
    bur.dt_start <= "2022-05-23T17:25:17"