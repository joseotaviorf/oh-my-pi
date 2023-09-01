WITH status_changes AS (
    SELECT
        la.id,
        la.id_file,
        NULL AS id_house,
        'SALE' AS business_context,
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
    UNION ALL
    SELECT
        bcd.id_lead,
        bcd.id_file,
        NULL AS id_house,
        bcd.business_context,
        bcda.status,
        NULL AS listing_status,
        MAP_KEYS(MAP_FILTER(FROM_JSON(bcda.status_reason, 'map<string, string>'), (k,v) -> v = 'true')) AS status_reasons,
        GET_JSON_OBJECT(la.owner, '$.phone') IS NOT NULL AS has_owner_info,
        TO_UTC_TIMESTAMP(bcda.ts_updated, 'America/Sao_Paulo') AS ts_status_started,
        bcda.year,
        bcda.month,
        bcda.day
    FROM
        datalake_brokers_supply_processor_clean.business_context_detail_aud AS bcda
    JOIN
        datalake_brokers_supply_processor.business_context_detail AS bcd
            ON bcda.id = bcd.id
    LEFT JOIN
        datalake_brokers_supply_processor_clean.lead_3p_aud AS la
            ON la.id = bcd.id_lead
            AND la.ts_updated <= bcda.ts_updated
    WHERE
        bcda.mod_status
        AND bcda.year = {year}
        AND bcda.month = {month}
        AND bcda.day = {day}
    QUALIFY -- We find the most recent row of lead_3p_aud at the time of the revision in business_context_detail
        ROW_NUMBER() OVER (PARTITION BY bcda.id, bcda.rev ORDER BY la.ts_updated DESC) = 1
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
        business_context,
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
        lbca.id_house,
        lbca.business_context,
        NULL AS status,
        IF(lbca.mod_status_closing = 1, lbca.status_closing, lbca.status) AS listing_status,
        FALSE AS is_waiting_for_enrichment,
        FALSE AS is_ineligible,
        FALSE AS is_discarded,
        TRUE AS has_owner_info,
        ts_revision AS ts_status_started,
        YEAR(ts_revision) AS year_revision,
        MONTH(ts_revision) AS month_revision,
        DAY(ts_revision) AS day_revision
    FROM
        datalake_brokers_supply_processor.lead_3p AS l
    JOIN
        datalake_ebdb_clean.house AS h
            ON h.id_external = l.uuid_lead
    JOIN
        datalake_ebdb_clean.listing_business_context_aud AS lbca
            ON lbca.id_house = h.id
    JOIN 
        datalake_ebdb_user.user_revision_entity AS rev
            ON rev.id = lbca.rev
    WHERE
        (lbca.business_context = 'SALE' AND (l.is_for_sale OR NOT l.is_for_rent))
        OR (lbca.business_context = 'RENT' AND l.is_for_rent)
    QUALIFY
        LAG(listing_status) OVER (
            PARTITION BY lbca.id_house,
            business_context ORDER BY lbca.rev
        ) IS DISTINCT FROM listing_status
        AND year_revision = {year}
        AND month_revision = {month}
        AND day_revision = {day}
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
    COALESCE(sea.id_file, bcd.id_file) AS id_file,
    sea.id_house,
    sea.business_context,
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
LEFT JOIN
    datalake_brokers_supply_processor.business_context_detail AS bcd
        ON bcd.id_lead = sea.id
        AND sea.business_context = bcd.business_context
