-- Contract-signed period keys use America/Sao_Paulo calendar date, not DATE(utc_ts).
-- DATE(ts) on UTC timestamps moves late-evening BRT signatures into the next month.
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
            ON YEAR(ad.date) = mp.year
            AND MONTH(ad.date) = mp.month
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
        IF(
            mp.metric IN ("GMV", "VGV_CONV"),
            "Sale price agreed",
            NULL
        ) AS cumulative_value_type,
        IF(
            mp.metric IN ("GMV", "VGV_CONV"),
            ao.agreement_value,
            NULL
        ) AS cumulative_value,
        mp_invalid.id IS NULL AS is_valid,
        FALSE AS is_compound_metric_part,
        IF(mp.metric IN ("GMV", "VGV_CONV"), TRUE, FALSE) AS is_cumulative_metric,
        DATE(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) AS dt_become_valid,
        IF(mp_invalid.id IS NOT NULL, ao.dt_contract_cancelled, NULL) AS ts_invalidation,
        ao.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_offers AS ao
    JOIN
        metric_period_process AS mp
            ON YEAR(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp.year
            AND MONTH(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp.month
            AND mp.metric IN ("CCV", "CCV_TQC", "GMV", "VGV_CONV")
    LEFT JOIN
        metric_period_process AS mp_invalid
            ON YEAR(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp_invalid.year
            AND MONTH(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp_invalid.month
            AND YEAR(ao.dt_contract_cancelled) = mp_invalid.year
            AND MONTH(ao.dt_contract_cancelled) = mp_invalid.month
            AND mp_invalid.metric = mp.metric
    WHERE
        ao.business_context = "SALE"
        AND (            
            (mp.metric = "CCV_TQC" AND ao.has_tqc IS TRUE)
            OR mp.metric IN ("CCV", "GMV", "VGV_CONV")
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
        IF(mp.metric = "VGV_ACQ", "Sale price agreed", NULL) AS cumulative_value_type,
        IF(mp.metric = "VGV_ACQ", ao.agreement_value, NULL) AS cumulative_value,
        mp_invalid.id IS NULL AND cfl.is_first_listing_valid IS TRUE AS is_valid,
        FALSE AS is_compound_metric_part,
        IF(mp.metric = "VGV_ACQ", TRUE, FALSE) AS is_cumulative_metric,
        DATE(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) AS dt_become_valid,
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
            ON YEAR(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp.year
            AND MONTH(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp.month
            AND mp.metric IN ("CCV_CIQ", "VGV_ACQ")
    LEFT JOIN
        metric_period_process AS mp_invalid
            ON YEAR(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp_invalid.year
            AND MONTH(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp_invalid.month
            AND YEAR(ao.dt_contract_cancelled) = mp_invalid.year
            AND MONTH(ao.dt_contract_cancelled) = mp_invalid.month
            AND mp_invalid.metric = mp.metric
    WHERE
        ao.business_context = "SALE"
        AND mp.metric IN ("CCV_CIQ", "VGV_ACQ")
        AND ao.is_ciq_first_listing IS TRUE
        AND ao.id_user_ciq IS NOT NULL
),
sale_vgv_total_attribution AS (
    SELECT
        ao.id_user,
        ao.id_agent,
        ao.uuid_person,
        ao.id_offer,
        ao.agreement_value,
        DATE(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) AS dt_contract_signed,
        ao.dt_contract_cancelled,
        ao.ts_updated,
        mp_invalid.id IS NOT NULL AS is_invalid_by_cancellation
    FROM
        datalake_tiers.agent_offers AS ao
    LEFT JOIN
        metric_period_process AS mp_invalid
            ON mp_invalid.metric = "VGV_TOTAL"
            AND YEAR(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp_invalid.year
            AND MONTH(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp_invalid.month
            AND YEAR(ao.dt_contract_cancelled) = mp_invalid.year
            AND MONTH(ao.dt_contract_cancelled) = mp_invalid.month
    WHERE
        ao.business_context = "SALE"
        AND ao.agent_profile = "AGENT"
        AND ao.ts_contract_signed IS NOT NULL
    UNION ALL
    SELECT
        id_user,
        id_agent,
        uuid_person,
        id_offer,
        agreement_value,
        dt_contract_signed,
        dt_contract_cancelled,
        ts_updated,
        is_invalid_by_cancellation
    FROM (
        SELECT
            ao.id_user_ciq AS id_user,
            cfl.id_agent,
            cfl.uuid_person,
            ao.id_offer,
            ao.agreement_value,
            DATE(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) AS dt_contract_signed,
            ao.dt_contract_cancelled,
            ao.ts_updated,
            mp_invalid.id IS NOT NULL AS is_invalid_by_cancellation,
            -- agent_offers is an audit table: the same id_offer can carry multiple
            -- agent_profile rows (AGENT, NEGOTIATION_EXECUTIVE, ...) and multiple
            -- revisions per profile as the offer is updated. This branch has no
            -- profile filter, so without this it pulls in every one of those rows
            -- for a signed offer instead of just the current one.
            ROW_NUMBER() OVER (PARTITION BY ao.id_offer ORDER BY ao.ts_updated DESC) AS rn_latest_revision
        FROM
            datalake_tiers.agent_offers AS ao
        JOIN
            datalake_tiers.ciq_first_listing AS cfl
                ON cfl.id_house = ao.id_house
                AND cfl.id_user = ao.id_user_ciq
                AND cfl.business_context = ao.business_context
        LEFT JOIN
            metric_period_process AS mp_invalid
                ON mp_invalid.metric = "VGV_TOTAL"
                AND YEAR(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp_invalid.year
            AND MONTH(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp_invalid.month
                AND YEAR(ao.dt_contract_cancelled) = mp_invalid.year
            AND MONTH(ao.dt_contract_cancelled) = mp_invalid.month
        WHERE
            ao.business_context = "SALE"
            AND ao.is_ciq_first_listing IS TRUE
            AND ao.id_user_ciq IS NOT NULL
            AND cfl.is_first_listing_valid IS TRUE
            AND ao.ts_contract_signed IS NOT NULL
    )
    WHERE
        rn_latest_revision = 1
),
sale_vgv_total_deduped_attribution AS (
    SELECT
        vta.id_user,
        MAX(vta.id_agent) AS id_agent,
        MAX(vta.uuid_person) AS uuid_person,
        vta.id_offer,
        MAX(vta.agreement_value) AS agreement_value,
        MAX(vta.dt_contract_signed) AS dt_contract_signed,
        MAX(vta.dt_contract_cancelled) AS dt_contract_cancelled,
        MAX(vta.ts_updated) AS ts_updated,
        BOOL_OR(vta.is_invalid_by_cancellation) AS is_invalid_by_cancellation
    FROM
        sale_vgv_total_attribution AS vta
    WHERE
        vta.id_user IS NOT NULL
    GROUP BY
        vta.id_user,
        vta.id_offer
),
sale_vgv_total_cumulative_metrics AS (
    SELECT
        vtd.id_user,
        vtd.id_agent,
        vtd.uuid_person,
        vtd.id_offer AS id_external_domain,
        mp.id AS id_metric_period,
        "OFFER" AS external_domain,
        "AGENT" AS agent_profile,
        NULL AS partial_metric,
        mp.metric AS final_metric,
        IF(
            mp_invalid.id IS NOT NULL OR vtd.is_invalid_by_cancellation,
            "CONTRACT CANCELLED AFTER SIGNED",
            "CONTRACT SIGNED"
        ) AS reason,
        "Sale price agreed" AS cumulative_value_type,
        vtd.agreement_value AS cumulative_value,
        mp_invalid.id IS NULL AND NOT vtd.is_invalid_by_cancellation AS is_valid,
        FALSE AS is_compound_metric_part,
        TRUE AS is_cumulative_metric,
        vtd.dt_contract_signed AS dt_become_valid,
        IF(
            mp_invalid.id IS NOT NULL OR vtd.is_invalid_by_cancellation,
            vtd.dt_contract_cancelled,
            NULL
        ) AS ts_invalidation,
        vtd.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        sale_vgv_total_deduped_attribution AS vtd
    JOIN
        metric_period_process AS mp
            ON YEAR(vtd.dt_contract_signed) = mp.year
            AND MONTH(vtd.dt_contract_signed) = mp.month
            AND mp.metric = "VGV_TOTAL"
    LEFT JOIN
        metric_period_process AS mp_invalid
            ON YEAR(vtd.dt_contract_signed) = mp_invalid.year
            AND MONTH(vtd.dt_contract_signed) = mp_invalid.month
            AND YEAR(vtd.dt_contract_cancelled) = mp_invalid.year
            AND MONTH(vtd.dt_contract_cancelled) = mp_invalid.month
            AND mp_invalid.metric = "VGV_TOTAL"
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
        DATE(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) AS dt_become_valid,
        IF(mp_invalid.id IS NOT NULL, ao.dt_contract_cancelled, NULL) AS ts_invalidation,
        ao.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_offers AS ao
    JOIN
        metric_period_process AS mp
            ON YEAR(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp.year
            AND MONTH(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp.month
            AND mp.metric IN ("OS2CCV_BY", "BP2CCV")
    LEFT JOIN
        metric_period_process AS mp_invalid
            ON YEAR(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp_invalid.year
            AND MONTH(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp_invalid.month
            AND YEAR(ao.dt_contract_cancelled) = mp_invalid.year
            AND MONTH(ao.dt_contract_cancelled) = mp_invalid.month
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
        DATE(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) AS dt_become_valid,
        NULL AS ts_invalidation,
        ao.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_offers AS ao
    JOIN
        metric_period_process AS mp
            ON YEAR(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp.year
            AND MONTH(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp.month
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
        DATE(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) AS dt_become_valid,
        NULL AS ts_invalidation,
        ao.ts_updated,
        mp.year,
        mp.month,
        mp.day
    FROM
        datalake_tiers.agent_offers AS ao
    JOIN
        metric_period_process AS mp
            ON YEAR(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp.year
            AND MONTH(FROM_UTC_TIMESTAMP(ao.ts_contract_signed, 'America/Sao_Paulo')) = mp.month
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
            ON YEAR(ao.ts_offer_submitted) = mp.year
            AND MONTH(ao.ts_offer_submitted) = mp.month
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
            ON YEAR(ao.ts_offer_submitted) = mp.year
            AND MONTH(ao.ts_offer_submitted) = mp.month
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
            ON YEAR(ap.ts_event) = mp.year
            AND MONTH(ap.ts_event) = mp.month
            AND mp.metric IN ("BP", "TP")
    WHERE
        (ap.business_context = "SALE" AND mp.metric = "BP")
        OR (ap.business_context = "RENT" AND mp.metric = "TP")
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 19, 20, 21
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
            ON YEAR(ap.ts_event) = mp.year
            AND MONTH(ap.ts_event) = mp.month
            AND mp.metric IN ("BP2CCV", "TP2CS")
    WHERE
        (ap.business_context = "SALE" AND mp.metric = "BP2CCV")
        OR (ap.business_context = "RENT" AND mp.metric = "TP2CS")
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 19, 20, 21
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
            ON YEAR(ap.ts_event) = mp.year
            AND MONTH(ap.ts_event) = mp.month
            AND mp.metric IN ("BP")
    JOIN
        datalake_tiers.agent_allocation AS aa
            ON aa.id_agent = ap.id_agent
            AND aa.id_metric_period = mp.id
    WHERE
        ap.business_context = "SALE"
        AND aa.id_parent_user IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 19, 20, 21
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
            ON YEAR(ap.ts_event) = mp.year
            AND MONTH(ap.ts_event) = mp.month
            AND mp.metric IN ("BP2CCV")
    JOIN
        datalake_tiers.agent_allocation AS aa
            ON aa.id_agent = ap.id_agent
            AND aa.id_metric_period = mp.id
    WHERE
        ap.business_context = "SALE"
        AND aa.id_parent_user IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 19, 20, 21
),
fl_fs_first_listing_candidates AS (
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
        mp.day,
        cfl.ts_original_first_listing,
        CASE
            WHEN cfl.business_context = "SALE" THEN 0
            ELSE 1
        END AS fl_fs_source_rank
    FROM
        datalake_tiers.ciq_first_listing AS cfl
    JOIN
        metric_period_process AS mp
            ON cfl.dt_compliance_general_rule BETWEEN DATE(mp.ts_interval_started) AND DATE(mp.ts_interval_ended)
            AND DATE_TRUNC('MONTH', cfl.ts_original_first_listing) = DATE_TRUNC('MONTH', mp.ts_interval_started)
            AND mp.metric IN ("FL_FS")
    WHERE
        cfl.business_context IN ("SALE", "RENT")
),
fl_fs_first_listing_ranked AS (
    SELECT
        ffc.id_user,
        ffc.id_agent,
        ffc.uuid_person,
        ffc.id_external_domain,
        ffc.id_metric_period,
        ffc.external_domain,
        ffc.agent_profile,
        ffc.partial_metric,
        ffc.final_metric,
        ffc.reason,
        ffc.cumulative_value_type,
        ffc.cumulative_value,
        ffc.is_valid,
        ffc.is_compound_metric_part,
        ffc.is_cumulative_metric,
        ffc.dt_become_valid,
        ffc.ts_invalidation,
        ffc.ts_updated,
        ffc.year,
        ffc.month,
        ffc.day,
        ROW_NUMBER() OVER (
            PARTITION BY
                ffc.id_user,
                ffc.id_external_domain
            ORDER BY
                CASE
                    WHEN ffc.is_valid IS TRUE THEN 0
                    ELSE 1
                END ASC,
                ffc.ts_original_first_listing ASC,
                ffc.fl_fs_source_rank ASC
        ) AS fl_fs_lifetime_rank
    FROM
        fl_fs_first_listing_candidates AS ffc
),
sale_first_listing_simple_metrics AS (
    SELECT
        ffr.id_user,
        ffr.id_agent,
        ffr.uuid_person,
        ffr.id_external_domain,
        ffr.id_metric_period,
        ffr.external_domain,
        ffr.agent_profile,
        ffr.partial_metric,
        ffr.final_metric,
        ffr.reason,
        ffr.cumulative_value_type,
        ffr.cumulative_value,
        ffr.is_valid,
        ffr.is_compound_metric_part,
        ffr.is_cumulative_metric,
        ffr.dt_become_valid,
        ffr.ts_invalidation,
        ffr.ts_updated,
        ffr.year,
        ffr.month,
        ffr.day
    FROM
        fl_fs_first_listing_ranked AS ffr
    WHERE
        ffr.fl_fs_lifetime_rank = 1
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
            ON cfl.dt_compliance_general_rule BETWEEN DATE(mp.ts_interval_started) AND DATE(mp.ts_interval_ended)
            AND DATE_TRUNC('MONTH', cfl.ts_original_first_listing) = DATE_TRUNC('MONTH', mp.ts_interval_started)
            AND mp.metric IN ("FL_FR")
    WHERE
        cfl.business_context = "RENT"
),
union_metrics AS (
    SELECT * FROM sale_contract_signed_simple_metrics
    UNION ALL
    SELECT * FROM sale_contract_signed_with_ciq_simple_metrics
    UNION ALL
    SELECT * FROM sale_vgv_total_cumulative_metrics
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