WITH status_changes AS (
    SELECT
        la.id,
        la.id_file,
        NULL AS id_house,
        la.status,
        NULL AS listing_status,
        MAP_KEYS(MAP_FILTER(FROM_JSON(status_reason, 'map<string, string>'), (k,v) -> v = 'true')) AS status_reasons,
        GET_JSON_OBJECT(owner, '$.phone') IS NOT NULL AS has_owner_info,
        TO_UTC_TIMESTAMP(ts_updated, 'America/Sao_Paulo') AS ts_status_started,
        year,
        month,
        day
    FROM
        datalake_brokers_supply_processor_clean.lead_3p_aud AS la
    WHERE
        mod_status
        AND year = {year}
        AND month = {month}
        AND day = {day}
),
enrichment_reasons AS (
    SELECT
        COLLECT_LIST(reason_name) AS reasons
    FROM
        datalake_gsheets_clean.supply_processor_status_reasons
    WHERE
        reason_type = 'ENRICHMENT_REASON'
),
ineligible_reasons AS (
    SELECT
        COLLECT_LIST(reason_name) AS reasons
    FROM
        datalake_gsheets_clean.supply_processor_status_reasons
    WHERE
        reason_type = 'INELIGIBLE_REASON'
),
discard_reasons AS (
    SELECT
        COLLECT_LIST(reason_name) AS reasons
    FROM
        datalake_gsheets_clean.supply_processor_status_reasons
    WHERE
        reason_type = 'DISCARD_REASON'
),
status_and_publications AS (
    SELECT
        id,
        id_file,
        id_house,
        status,
        listing_status,
        COALESCE(ARRAYS_OVERLAP(sc.status_reasons, er.reasons), FALSE) AS is_waiting_for_enrichment,
        COALESCE(ARRAYS_OVERLAP(sc.status_reasons, ir.reasons), FALSE) AS is_ineligible,
        COALESCE(ARRAYS_OVERLAP(sc.status_reasons, dr.reasons), FALSE) AS is_discarded,
        has_owner_info,
        ts_status_started,
        year,
        month,
        day
    FROM
        status_changes AS sc,
        enrichment_reasons AS er,
        ineligible_reasons AS ir,
        discard_reasons AS dr
    UNION ALL
    SELECT DISTINCT
        l.id,
        NULL AS id_file,
        sls.id_house,
        NULL AS status,
        sls.status_history AS listing_status,
        FALSE AS is_waiting_for_enrichment,
        FALSE AS is_ineligible,
        FALSE AS is_discarded,
        TRUE AS has_owner_info,
        sls.ts_status_started,
        {year} AS year,
        {month} AS month,
        {day} AS day
    FROM
        datalake_brokers_supply_processor.lead_3p AS l
    JOIN
        datalake_ebdb_clean.house AS h
            ON h.id_external = l.uuid_lead
    JOIN
        datalake_sale_listings.sale_listing_status AS sls
            ON sls.id_house = h.id
    WHERE
        YEAR(ts_status_started) = {year}
        AND MONTH(ts_status_started) = {month}
        AND DAY(ts_status_started) = {day}
),
last_id AS (
    SELECT
        COALESCE(MAX(id_status_change), 0) AS id_last_status_change
    FROM
        datalake_rede_supply.simplified_lead_3p_status_changes
    WHERE
        year != {year}
        OR month != {month}
        OR day != {day}
)
SELECT
    id_last_status_change + MONOTONICALLY_INCREASING_ID() + 1 AS id_status_change,
    sea.id AS id_lead_3p,
    COALESCE(sea.id_file, l.id_file) AS id_file,
    sea.id_house,
    sea.status,
    sea.listing_status,
    sea.is_waiting_for_enrichment,
    sea.is_ineligible,
    sea.is_discarded,
    sea.has_owner_info,
    sea.ts_status_started,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    status_and_publications AS sea,
    last_id AS li
JOIN
    datalake_brokers_supply_processor.lead_3p AS l
        ON l.id = sea.id
