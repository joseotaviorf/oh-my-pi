WITH metric_period_process AS (
    SELECT DISTINCT
        mp.id,
        mp.metric,
        mp.dt_init,
        mp.dt_end,
        mp. ts_interval_started,
        mp. ts_interval_ended,
        -- keeping partitions immutable for the merge on function
        YEAR(mp.dt_init) AS year,
        MONTH(mp.dt_init) AS month,
        DAY(mp.dt_init) AS day
    FROM
        datalake_tiers.metric_period AS mp
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN mp.dt_init AND mp.dt_end
    WHERE
        ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND mp.status = "VALID"
),
sale_contract_signed_simple_metrics AS (
    SELECT
        ao.id_user,
        ao.id_agent,
        ao.uuid_person,
        ao.id_offer AS id_external_domain,
        mp.id AS id_metric_period,
        "OFFER" AS external_domain,
        ao.agent_profile,
        NULL AS partial_metric,
        mp.metric AS final_metric,
        IF(mp_invalid.id IS NOT NULL, "CONTRACT CANCELLED AFTER SIGNED", "CONTRACT SIGNED") AS reason,
        IF(mp.metric = "GMV", "Sale price agreed", NULL) AS cumulative_value_type,
        IF(mp.metric = "GMV", ao.agreement_value, NULL) AS cumulative_value,
        mp_invalid.id IS NULL AS is_valid,
        FALSE AS is_compound_metric_part,
        IF(mp.metric = "GMV", TRUE, FALSE) AS is_cumulative_metric,
        DATE(ao.ts_contract_signed) AS dt_become_valid,
        IF(mp_invalid.id IS NOT NULL, ao.dt_contract_cancelled, NULL) AS ts_invalidation,
        ao.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_offers AS ao
    JOIN
        metric_period_process AS mp
            ON DATE(ao.ts_contract_signed) BETWEEN mp.dt_init AND mp.dt_end
            AND mp.metric IN ("CCV", "CCV_TQC", "GMV")
    LEFT JOIN
        metric_period_process AS mp_invalid
            ON DATE(ao.ts_contract_signed) BETWEEN mp_invalid.dt_init AND mp_invalid.dt_end
            AND ao.dt_contract_cancelled BETWEEN mp_invalid.dt_init AND mp_invalid.dt_end
            AND mp_invalid.metric = mp.metric
    WHERE
        ao.business_context = "SALE"
        AND (            
            (mp.metric = "CCV_TQC" AND ao.has_tqc IS TRUE)
            OR mp.metric IN ("CCV", "GMV")
        )
),
sale_contract_signed_with_ciq_simple_metrics AS (
    SELECT
        ao.id_user_ciq AS id_user,
        cfl.id_agent,
        cfl.uuid_person,
        ao.id_offer AS id_external_domain,
        mp.id AS id_metric_period,
        "OFFER" AS external_domain,
        "CIQ" AS agent_profile,
        NULL AS partial_metric,
        mp.metric AS final_metric,
        IF(
            mp_invalid.id IS NOT NULL, 
            "CONTRACT CANCELLED AFTER SIGNED", 
            IF(
                cfl.is_first_listing_valid IS FALSE, 
                ARRAY_JOIN(cfl.invalidation_reasons, ' | '),
                "FIRST LISTING VALID | CONTRACT SIGNED"
            )
        ) AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        mp_invalid.id IS NULL AND cfl.is_first_listing_valid IS TRUE AS is_valid,
        FALSE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(ao.ts_contract_signed) AS dt_become_valid,
        IF(
            mp_invalid.id IS NOT NULL OR cfl.is_first_listing_valid IS FALSE, 
            COALESCE(ao.dt_contract_cancelled, mp.dt_end), 
            NULL
        ) AS ts_invalidation,
        ao.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_offers AS ao
    JOIN
        datalake_tiers.ciq_first_listing AS cfl 
            ON cfl.id_house = ao.id_house
            AND cfl.id_user = ao.id_user_ciq
            AND cfl.business_context = ao.business_context
    JOIN
        metric_period_process AS mp
            ON DATE(ao.ts_contract_signed) BETWEEN mp.dt_init AND mp.dt_end
            AND mp.metric IN ("CCV_CIQ")
    LEFT JOIN
        metric_period_process AS mp_invalid
            ON DATE(ao.ts_contract_signed) BETWEEN mp_invalid.dt_init AND mp_invalid.dt_end
            AND ao.dt_contract_cancelled BETWEEN mp_invalid.dt_init AND mp_invalid.dt_end
            AND mp_invalid.metric = mp.metric
    WHERE
        ao.business_context = "SALE"
        AND mp.metric = "CCV_CIQ" 
        AND ao.is_ciq_first_listing IS TRUE
        AND ao.id_user_ciq IS NOT NULL
),
sale_contract_signed_compound_metrics AS (
    SELECT
        ao.id_user,
        ao.id_agent,
        ao.uuid_person,
        ao.id_offer AS id_external_domain,
        mp.id AS id_metric_period,
        "OFFER" AS external_domain,
        ao.agent_profile,
        "CCV" AS partial_metric,
        mp.metric AS final_metric,
        IF(mp_invalid.id IS NOT NULL, "CONTRACT CANCELLED AFTER SIGNED", "CONTRACT SIGNED") AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        mp_invalid.id IS NULL AS is_valid,
        TRUE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(ao.ts_contract_signed) AS dt_become_valid,
        IF(mp_invalid.id IS NOT NULL, ao.dt_contract_cancelled, NULL) AS ts_invalidation,
        ao.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_offers AS ao
    JOIN
        metric_period_process AS mp
            ON DATE(ao.ts_contract_signed) BETWEEN mp.dt_init AND mp.dt_end
            AND mp.metric IN ("OS2CCV_BY", "BP2CCV")
    LEFT JOIN
        metric_period_process AS mp_invalid
            ON DATE(ao.ts_contract_signed) BETWEEN mp_invalid.dt_init AND mp_invalid.dt_end
            AND ao.dt_contract_cancelled BETWEEN mp_invalid.dt_init AND mp_invalid.dt_end
            AND mp_invalid.metric = mp.metric
    WHERE
        ao.business_context = "SALE"
),
rent_contract_signed_simple_metrics AS (
    SELECT
        ao.id_user,
        ao.id_agent,
        ao.uuid_person,
        ao.id_contract AS id_external_domain,
        mp.id AS id_metric_period,
        "CONTRACT" AS external_domain,
        ao.agent_profile,
        NULL AS partial_metric,
        mp.metric AS final_metric,
        "CONTRACT SIGNED" AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        TRUE AS is_valid,
        FALSE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(ao.ts_contract_signed) AS dt_become_valid,
        NULL AS ts_invalidation,
        ao.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_offers AS ao
    JOIN
        metric_period_process AS mp
            ON DATE(ao.ts_contract_signed) BETWEEN mp.dt_init AND mp.dt_end
            AND mp.metric IN ("CS")
    WHERE
        ao.business_context = "RENT"
),
rent_contract_signed_compound_metrics AS (
    SELECT
        ao.id_user,
        ao.id_agent,
        ao.uuid_person,
        ao.id_contract AS id_external_domain,
        mp.id AS id_metric_period,
        "CONTRACT" AS external_domain,
        ao.agent_profile,
        "CS" AS partial_metric,
        mp.metric AS final_metric,
        "CONTRACT SIGNED" AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        TRUE AS is_valid,
        TRUE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(ao.ts_contract_signed) AS dt_become_valid,
        NULL AS ts_invalidation,
        ao.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_offers AS ao
    JOIN
        metric_period_process AS mp
            ON DATE(ao.ts_contract_signed) BETWEEN mp.dt_init AND mp.dt_end
            AND mp.metric IN ("TP2CS")
    WHERE
        ao.business_context = "RENT"
),
buyer_with_offer_submited_simple_metrics AS (
    SELECT
        ao.id_user,
        ao.id_agent,
        ao.uuid_person,
        ao.id_offer AS id_external_domain,
        mp.id AS id_metric_period,
        "OFFER" AS external_domain,
        ao.agent_profile,
        NULL AS partial_metric,
        mp.metric AS final_metric,
        "OFFER SUBMITED" AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        TRUE AS is_valid,
        FALSE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(ao.ts_offer_submitted) AS dt_become_valid,
        NULL AS ts_invalidation,
        ao.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_offers AS ao
    JOIN
        metric_period_process AS mp
            ON DATE(ao.ts_offer_submitted) BETWEEN mp.dt_init AND mp.dt_end
            AND mp.metric = "OS_BY"
    WHERE
        ao.business_context = "SALE"
),
buyer_with_offer_submited_compound_metrics AS (
    SELECT
        ao.id_user,
        ao.id_agent,
        ao.uuid_person,
        ao.id_offer AS id_external_domain,
        mp.id AS id_metric_period,
        "OFFER" AS external_domain,
        ao.agent_profile,
        "OS_BY" AS partial_metric,
        mp.metric AS final_metric,
        "OFFER SUBMITED" AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        TRUE AS is_valid,
        TRUE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(ao.ts_offer_submitted) AS dt_become_valid,
        NULL AS ts_invalidation,
        ao.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_offers AS ao
    JOIN
        metric_period_process AS mp
            ON DATE(ao.ts_offer_submitted) BETWEEN mp.dt_init AND mp.dt_end
            AND mp.metric IN ("OS2CCV_BY")
    WHERE
        ao.business_context = "SALE"
),
broker_prospects_simple_metrics AS (
    SELECT
        ap.id_user,
        ap.id_agent,
        ap.uuid_person,
        ap.id_prospect AS id_external_domain,
        mp.id AS id_metric_period,
        "PROSPECT" AS external_domain,
        "AGENT" AS agent_profile,
        NULL AS partial_metric,
        mp.metric AS final_metric,
        "NEW OR RECOVERED PROSPECT" AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        TRUE AS is_valid,
        FALSE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(MIN(ap.ts_event)) AS dt_become_valid,
        NULL AS ts_invalidation,
        MAX(ap.ts_event) AS ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_prospects AS ap
    JOIN
        metric_period_process AS mp
            ON DATE(ap.ts_event) BETWEEN mp.dt_init AND mp.dt_end
            AND mp.metric IN ("BP", "TP")
    WHERE
        (ap.business_context = "SALE" AND mp.metric = "BP")
        OR (ap.business_context = "RENT" AND mp.metric = "TP")
    GROUP BY ALL
),
broker_prospects_compound_metrics AS (
    SELECT
        ap.id_user,
        ap.id_agent,
        ap.uuid_person,
        ap.id_prospect AS id_external_domain,
        mp.id AS id_metric_period,
        "PROSPECT" AS external_domain,
        "AGENT" AS agent_profile,
        IF(mp.metric = "BP2CCV", "BP", "TP") AS partial_metric,
        mp.metric AS final_metric,
        "NEW OR RECOVERED PROSPECT" AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        TRUE AS is_valid,
        TRUE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(MIN(ap.ts_event)) AS dt_become_valid,
        NULL AS ts_invalidation,
        MAX(ap.ts_event) AS ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_prospects AS ap
    JOIN
        metric_period_process AS mp
            ON DATE(ap.ts_event) BETWEEN mp.dt_init AND mp.dt_end
            AND mp.metric IN ("BP2CCV", "TP2CS")
    WHERE
        (ap.business_context = "SALE" AND mp.metric = "BP2CCV")
        OR (ap.business_context = "RENT" AND mp.metric = "TP2CS")
    GROUP BY ALL
),
negotiation_executive_prospects_simple_metrics AS (
    SELECT
        aa.id_parent_user AS id_user,
        aa.id_parent_agent AS id_agent,
        aa.uuid_parent_person AS uuid_person,
        ap.id_prospect AS id_external_domain,
        mp.id AS id_metric_period,
        "PROSPECT" AS external_domain,
        "NEGOTIATION_EXECUTIVE" AS agent_profile,
        NULL AS partial_metric,
        mp.metric AS final_metric,
        "NEW OR RECOVERED PROSPECT" AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        TRUE AS is_valid,
        FALSE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(MIN(ap.ts_event)) AS dt_become_valid,
        NULL AS ts_invalidation,
        MAX(ap.ts_event) AS ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_prospects AS ap
    JOIN
        metric_period_process AS mp
            ON DATE(ap.ts_event) BETWEEN mp.dt_init AND mp.dt_end
            AND mp.metric IN ("BP")
    JOIN
        datalake_tiers.agent_allocation AS aa
            ON aa.id_agent = ap.id_agent
            AND aa.id_metric_period = mp.id
    WHERE
        ap.business_context = "SALE"
        AND aa.id_parent_user IS NOT NULL
    GROUP BY ALL
),
negotiation_executive_prospects_compound_metrics AS (
    SELECT
        aa.id_parent_user AS id_user,
        aa.id_parent_agent AS id_agent,
        aa.uuid_parent_person AS uuid_person,
        ap.id_prospect AS id_external_domain,
        mp.id AS id_metric_period,
        "PROSPECT" AS external_domain,
        "NEGOTIATION_EXECUTIVE" AS agent_profile,
        "BP" AS partial_metric,
        mp.metric AS final_metric,
        "NEW OR RECOVERED PROSPECT" AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        TRUE AS is_valid,
        TRUE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(MIN(ap.ts_event)) AS dt_become_valid,
        NULL AS ts_invalidation,
        MAX(ap.ts_event) AS ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_prospects AS ap
    JOIN
        metric_period_process AS mp
            ON DATE(ap.ts_event) BETWEEN mp.dt_init AND mp.dt_end
            AND mp.metric IN ("BP2CCV")
    JOIN
        datalake_tiers.agent_allocation AS aa
            ON aa.id_agent = ap.id_agent
            AND aa.id_metric_period = mp.id
    WHERE
        ap.business_context = "SALE"
        AND aa.id_parent_user IS NOT NULL
    GROUP BY ALL
),
sale_first_listing_simple_metrics AS (
    SELECT
        cfl.id_user,
        cfl.id_agent,
        cfl.uuid_person,
        cfl.id_house AS id_external_domain,
        mp.id AS id_metric_period,
        "HOUSE" AS external_domain,
        "CIQ" AS agent_profile,
        NULL AS partial_metric,
        mp.metric AS final_metric,
        IF(
            cfl.is_first_listing_valid IS FALSE, 
            ARRAY_JOIN(cfl.invalidation_reasons, ' | '),
            "FIRST LISTING VALID"
        ) AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        cfl.is_first_listing_valid IS TRUE AS is_valid,
        FALSE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(cfl.dt_compliance_general_rule) AS dt_become_valid,
        IF(cfl.is_first_listing_valid IS FALSE, mp.dt_end, NULL) AS ts_invalidation,
        DATE('{load_end_date}') AS ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.ciq_first_listing AS cfl
    JOIN
        metric_period_process AS mp
            ON cfl.dt_compliance_general_rule BETWEEN DATE(mp.ts_interval_started) AND DATE(mp.ts_interval_ended)
            AND mp.metric IN ("FL_FS")
    WHERE
        cfl.business_context = "SALE"
),
rent_first_listing_simple_metrics AS (
    SELECT
        cfl.id_user,
        cfl.id_agent,
        cfl.uuid_person,
        cfl.id_house AS id_external_domain,
        mp.id AS id_metric_period,
        "HOUSE" AS external_domain,
        "CIQ" AS agent_profile,
        NULL AS partial_metric,
        mp.metric AS final_metric,
        IF(
            cfl.is_first_listing_valid IS FALSE, 
            ARRAY_JOIN(cfl.invalidation_reasons, ' | '),
            "FIRST LISTING VALID"
        ) AS reason,
        NULL AS cumulative_value_type,
        NULL AS cumulative_value,
        cfl.is_first_listing_valid IS TRUE AS is_valid,
        FALSE AS is_compound_metric_part,
        FALSE AS is_cumulative_metric,
        DATE(cfl.dt_compliance_general_rule) AS dt_become_valid,
        IF(cfl.is_first_listing_valid IS FALSE, mp.dt_end, NULL) AS ts_invalidation,
        DATE('{load_end_date}') AS ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.ciq_first_listing AS cfl
    JOIN
        metric_period_process AS mp
            ON cfl.dt_compliance_general_rule BETWEEN DATE(mp.ts_interval_started) AND DATE(mp.ts_interval_ended + INTERVAL 2 DAY)
            AND mp.metric IN ("FL_FR")
    WHERE
        cfl.business_context = "RENT"
),
union_metrics AS (
    SELECT * FROM sale_contract_signed_simple_metrics
    UNION ALL
    SELECT * FROM sale_contract_signed_with_ciq_simple_metrics
    UNION ALL
    SELECT * FROM sale_contract_signed_compound_metrics
    UNION ALL
    SELECT * FROM rent_contract_signed_simple_metrics
    UNION ALL
    SELECT * FROM rent_contract_signed_compound_metrics
    UNION ALL
    SELECT * FROM buyer_with_offer_submited_simple_metrics
    UNION ALL
    SELECT * FROM buyer_with_offer_submited_compound_metrics
    UNION ALL
    SELECT * FROM broker_prospects_simple_metrics
    UNION ALL
    SELECT * FROM broker_prospects_compound_metrics
    UNION ALL
    SELECT * FROM negotiation_executive_prospects_simple_metrics
    UNION ALL
    SELECT * FROM negotiation_executive_prospects_compound_metrics
    UNION ALL
    SELECT * FROM sale_first_listing_simple_metrics
    UNION ALL
    SELECT * FROM rent_first_listing_simple_metrics
),
metric_events AS (
    SELECT
        XXHASH64(
            um.id_user,
            um.id_external_domain,
            um.id_metric_period,
            um.agent_profile,
            COALESCE(um.partial_metric, '-1')
        ) AS id_metric_event,
        um.id_user,
        um.id_agent,
        um.uuid_person,
        um.id_external_domain,
        um.id_metric_period,
        um.external_domain,
        um.agent_profile,
        um.partial_metric,
        um.final_metric,
        um.reason,
        um.cumulative_value_type,
        um.cumulative_value,
        um.is_valid,
        um.is_compound_metric_part,
        um.is_cumulative_metric,
        ROW_NUMBER() OVER (
            PARTITION BY 
                um.id_user,
                um.id_external_domain,
                um.id_metric_period,
                um.agent_profile,
                COALESCE(um.partial_metric, '-1') 
            ORDER BY 
                um.ts_updated DESC, 
                um.dt_become_valid DESC
        ) = 1 AS is_latest_event,
        um.dt_become_valid,
        um.ts_invalidation,
        um.ts_updated,
        um.year,
        um.month,
        um.day
    FROM
        union_metrics AS um
)
SELECT
    me.id_metric_event,
    me.id_user,
    me.id_agent,
    me.uuid_person,
    me.id_external_domain,
    me.id_metric_period,
    me.external_domain,
    me.agent_profile,
    me.partial_metric,
    me.final_metric,
    me.reason,
    me.cumulative_value_type,
    me.cumulative_value,
    me.is_valid,
    me.is_compound_metric_part,
    me.is_cumulative_metric,
    me.dt_become_valid,
    me.ts_invalidation,
    me.ts_updated,
    me.year,
    me.month,
    me.day
FROM
    metric_events AS me
WHERE
    me.is_latest_event IS TRUE