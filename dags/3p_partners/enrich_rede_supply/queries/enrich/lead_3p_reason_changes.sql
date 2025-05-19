WITH exploded_reasons AS (
    SELECT
        id,
        id_file,
        'SALE' AS business_context,
        EXPLODE(FROM_JSON(status_reason, 'map<string, string>')) AS (reason, value),
        TO_UTC_TIMESTAMP(ts_updated, 'America/Sao_Paulo') AS ts_reason_started
    FROM
        datalake_brokers_supply_processor_clean.lead_3p_aud
    WHERE
        mod_status_reason
    UNION ALL
    SELECT
        bcd.id_lead AS id,
        bcd.id_file,
        bcd.business_context,
        EXPLODE(FROM_JSON(bcda.status_reason, 'map<string, string>')) AS (reason, value),
        TO_UTC_TIMESTAMP(bcda.ts_updated, 'America/Sao_Paulo') AS ts_reason_started
    FROM
        datalake_brokers_supply_processor_clean.business_context_detail_aud AS bcda
    JOIN
        datalake_brokers_supply_processor.business_context_detail AS bcd
            ON bcda.id = bcd.id
    WHERE
        mod_status_reason
),
previous_value_aux AS (
    SELECT *,
        LAG(value) OVER (PARTITION BY id, business_context, reason ORDER BY ts_reason_started) AS previous_value
    FROM
        exploded_reasons
),
reason_ended_aux AS (
    SELECT *,
        reason_type,
        reason_type = 'INELIGIBLE_REASON' AS is_ineligible_reason,
        reason_type = 'DISCARD_REASON' AS is_discard_reason,
        reason_type = 'ENRICHMENT_REASON' AS is_enrichment_reason,
        LEAD(ts_reason_started) OVER(PARTITION BY id, business_context, reason ORDER BY ts_reason_started) AS ts_reason_ended
    FROM
        previous_value_aux AS pva
    JOIN
        datalake_gsheets_clean.supply_processor_status_reasons AS sr
            ON pva.reason = sr.reason_name
    WHERE
        previous_value IS DISTINCT FROM value
),
forced_end_aux AS (
    SELECT
        rea.id AS id_lead_3p,
        sc.id_company_hubspot,
        sc.uuid_company,
        rea.id_file,
        rea.business_context,
        reason,
        reason_type,
        sc.status AS status_when_reason_started,
        sc.growth_status AS growth_status_when_reason_started,
        COALESCE(sc_end.status, ll.status) AS status_when_reason_ended,
        COALESCE(sc_end.growth_status, ll.growth_status) AS growth_status_when_reason_ended,
        DATEDIFF(COALESCE(ts_reason_ended, ll.ts_status_started), ts_reason_started) AS days_in_reason,
        -- The last left join with lead_3p_status_changes can bring more than one result
        -- We only want the most recent one
        ROW_NUMBER() OVER(PARTITION BY rea.id, rea.business_context, reason, ts_reason_started ORDER BY ll.ts_status_started NULLS LAST) AS rw,
        sc.is_waiting_for_enrichment AS is_waiting_for_enrichment_when_reason_started,
        sc.is_ineligible AS is_ineligible_when_reason_started,
        sc.is_discarded AS is_discarded_when_reason_started,
        COALESCE(sc_end.is_waiting_for_enrichment, ll.is_waiting_for_enrichment) AS is_waiting_for_enrichment_when_reason_ended,
        COALESCE(sc_end.is_ineligible, ll.is_ineligible) AS is_ineligible_when_reason_ended,
        COALESCE(sc_end.is_discarded, ll.is_discarded) AS is_discarded_when_reason_ended,
        rea.ts_reason_ended IS NOT NULL AS is_requirement_met,
        is_ineligible_reason,
        is_discard_reason,
        is_enrichment_reason,
        ts_reason_started,
        COALESCE(rea.ts_reason_ended, ll.ts_status_started) AS ts_reason_ended
    FROM
        reason_ended_aux AS rea
    LEFT JOIN
        datalake_rede_supply.lead_3p_status_changes AS sc
            ON rea.id = sc.id_lead_3p
            AND rea.business_context = sc.business_context
            AND rea.ts_reason_started >= sc.ts_status_started
            AND rea.ts_reason_started < COALESCE(sc.ts_status_ended, NOW())
    LEFT JOIN
        datalake_rede_supply.lead_3p_status_changes AS sc_end
            ON rea.id = sc_end.id_lead_3p
            AND rea.business_context = sc_end.business_context
            AND rea.ts_reason_ended >= sc_end.ts_status_started
            AND rea.ts_reason_ended < COALESCE(sc_end.ts_status_ended, NOW())
    LEFT JOIN
        datalake_rede_supply.lead_3p_status_changes AS ll -- this is meant to find the next times when the lead was discarded or not eligible
            ON is_enrichment_reason
            AND rea.business_context = ll.business_context
            AND ts_reason_ended IS NULL
            AND rea.id = ll.id_lead_3p
            AND rea.ts_reason_started <= ll.ts_status_started
            AND (ll.is_discarded OR ll.is_ineligible)
    WHERE
        value = 'true'
)
SELECT
    id_lead_3p,
    id_company_hubspot,
    uuid_company,
    id_file,
    business_context,
    reason,
    reason_type,
    status_when_reason_started,
    growth_status_when_reason_started,
    status_when_reason_ended,
    growth_status_when_reason_ended,
    days_in_reason,
    is_ineligible_reason,
    is_discard_reason,
    is_enrichment_reason,
    is_waiting_for_enrichment_when_reason_started,
    is_ineligible_when_reason_started,
    is_discarded_when_reason_started,
    is_waiting_for_enrichment_when_reason_ended,
    is_ineligible_when_reason_ended,
    is_discarded_when_reason_ended,
    is_requirement_met,
    ts_reason_started,
    ts_reason_ended,
    NOW() AS ts_load
FROM
    forced_end_aux
WHERE
    rw = 1