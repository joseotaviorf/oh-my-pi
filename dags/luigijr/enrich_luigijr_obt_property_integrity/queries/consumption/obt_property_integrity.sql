-- OBT: Property Integrity — enriched offboarding view  (metrics/OBT Property Integrity.md)
-- Dialect: Trino (data lake)
-- Owner: Property Integrity + Data Engineering
-- Last validated: 2026-07-24 (pending re-validation: table rename below + has_disputes not yet test-run against Trino)
--
-- Builds on top of dw_offboarding.obt_offboarding, adding annotation-derived fields
-- (UI flow variants, Kirk test flags, auto-pricing group, conversational mediation group),
-- Kirk's internal analysis-mode flag (kirk_analysis_mode — a general-purpose column meant
-- to carry whichever Kirk-internal experiment is live; currently the postfilter A/B test),
-- two mediation-cause flags, tenant-contestation media/cost fields, a CDP-sourced
-- human-contestation-analysis flag (has_human_contestation_analysis), and a hardened
-- has_disputes target-metric flag (total_tenant_contestation > 0 OR
-- repairs_added_by_owner_review > 0).
-- Source doc: https://docs.google.com/document/d/1K65uzKG8xRiu40Y7UqUZykvmr02SOlO4cBDmIfQs5QI
WITH constants AS (
    SELECT
        'native_timeline'                  AS TIMELINE_KEY,
        'native_dispute_overview'          AS DISPUTE_OVERVIEW_KEY,
        'native_initial_review'            AS NATIVE_FIRST_REVIEW,
        'item_verification_rollout'        AS KIRK_TEST_KEY,
        'eviction_repair_analysis_rollout' AS EVICTION_KIRK_TEST_KEY,
        'automatic-repair-pricing'         AS AUTO_PRICING_TEST_KEY,
        'repair-mediation-rollout'         AS MEDIATION_TEST_KEY,
        TIMESTAMP '2026-05-18 00:00:00 UTC' AS AUTO_PRICING_ROLLOUT_START
),
deduped_annotations AS (
    SELECT
        a.uuid_inspection,
        a.key,
        a.value,
        a.ts_created,
        ROW_NUMBER() OVER (
            PARTITION BY a.uuid_inspection, a.key
            ORDER BY a.ts_created DESC
        ) AS row_num
    FROM datalake_inspection_services_clean.annotation a
    CROSS JOIN constants c
    WHERE a.key IN (
        c.TIMELINE_KEY,
        c.DISPUTE_OVERVIEW_KEY,
        c.NATIVE_FIRST_REVIEW,
        c.KIRK_TEST_KEY,
        c.EVICTION_KIRK_TEST_KEY,
        c.AUTO_PRICING_TEST_KEY,
        c.MEDIATION_TEST_KEY
    )
),
kirk_analysis_latest AS (
    -- Collapse CDC (Debezium) row-versions to the current state per Kirk analysis record.
    SELECT
        id_inspection,
        id_analysis,
        analysis_status,
        analysis_mode,
        ts_created,
        ROW_NUMBER() OVER (
            PARTITION BY id_analysis
            ORDER BY ts_updated DESC
        ) AS version_num
    FROM datalake_kirk_clean.ai_inspection_analysis
),
kirk_analysis AS (
    -- One row per inspection: the analysis that completed wins over a later failed retry;
    -- otherwise the most recent attempt.
    SELECT
        id_inspection,
        analysis_mode,
        ROW_NUMBER() OVER (
            PARTITION BY id_inspection
            ORDER BY (UPPER(analysis_status) = 'COMPLETED') DESC, ts_created DESC
        ) AS row_num
    FROM kirk_analysis_latest
    WHERE version_num = 1
),
tenant_contestation_media AS (
    SELECT
        CAST(frr.sk_inspection AS VARCHAR) AS sk_inspection,  -- fix: bigint → varchar para join com obt
        BOOL_OR(fc.has_media = TRUE) AS has_tenant_contestation_media
    FROM dw_inspections.fact_repair_request frr
    INNER JOIN dw_inspections.fact_contestation fc
        ON frr.sk_repair_request = fc.sk_repair_request
    WHERE fc.is_contested_by_tenant = TRUE
    GROUP BY frr.sk_inspection
),
ar_cost_contested_repairs AS (
    SELECT
        CAST(frr.sk_inspection AS VARCHAR) AS sk_inspection,  -- fix: bigint → varchar para join com obt
        SUM(CAST(drr.cost AS DOUBLE)) AS total_ar_cost_contested_repairs
    FROM dw_inspections.fact_repair_request frr
    INNER JOIN dw_inspections.dim_repair_request drr
        ON frr.sk_repair_request = drr.id_repair_request
    WHERE frr.has_tenant_contestation = TRUE
    GROUP BY frr.sk_inspection
),
-- Lia's own conversation/negotiation record (repair_request_mediation), distinct from the
-- traditional human-mediation ticket (has_mediation_ticket). One inspection can only have one
-- active Lia negotiation, but dedup defensively on the latest by ts_created.
deduped_lia_mediation AS (
    SELECT
        id_inspection,
        is_completed,
        is_tenant_agreed,
        applied_discount_amount,
        ts_created,
        ts_completed,
        id_client_side
    FROM (
        SELECT
            rrm.id_inspection,
            rrm.is_completed,
            rrm.is_tenant_agreed,
            rrm.applied_discount_amount,
            rrm.ts_created,
            rrm.ts_completed,
            i.id_client_side,
            ROW_NUMBER() OVER (
                PARTITION BY rrm.id_inspection
                ORDER BY rrm.ts_created DESC
            ) AS row_num
        FROM datalake_inspection_services_clean.repair_request_mediation rrm
        INNER JOIN datalake_inspection_services_clean.inspection i
            ON i.id_inspection = rrm.id_inspection
        WHERE COALESCE(rrm.op_cdc, 'c') <> 'd'
          AND COALESCE(i.op_cdc, 'c') <> 'd'
    ) ranked
    WHERE row_num = 1
),
lia_timeout_notifications AS (
    SELECT
        split_part(id_entity, '_tenant_', 1) AS entity_uuid,
        id_user
    FROM datalake_jaiminho_clean.user_notifications
    WHERE template = 'pi_aimediationtimeout_tenant_whatsapp'
      AND entity_name = 'Inspections'
),
-- Matches Lia's mediation window to a samia chatbot session via the tenant's
-- id_user (resolved from the timeout HSM), then to that session's messages.
lia_mediation_sessions AS (
    SELECT DISTINCT
        lia.id_inspection,
        lia.ts_created,
        lia.ts_completed,
        s.id_sauron_session
    FROM deduped_lia_mediation lia
    LEFT JOIN lia_timeout_notifications n
        ON n.entity_uuid = CAST(lia.id_client_side AS VARCHAR)
    JOIN datalake_chatbot.sessions s
        ON CAST(s.id_user AS BIGINT) = n.id_user
        AND s.bot = 'samia'
        AND s.ts_created BETWEEN lia.ts_created - INTERVAL '1' HOUR
                             AND COALESCE(lia.ts_completed, CURRENT_TIMESTAMP) + INTERVAL '1' HOUR
),
lia_mediation_flags AS (
    SELECT
        ms.id_inspection,
        max(CASE WHEN msg.role = 'HUMAN' THEN 1 ELSE 0 END) AS has_human_message_any,
        max(CASE
            WHEN msg.role = 'HUMAN'
             AND ms.ts_completed IS NOT NULL
             AND msg.ts_created <= ms.ts_completed
            THEN 1 ELSE 0
        END) AS has_human_message_before_timeout
    FROM lia_mediation_sessions ms
    LEFT JOIN datalake_chatbot.messages msg
        ON CAST(msg.id_sauron_session AS VARCHAR) = CAST(ms.id_sauron_session AS VARCHAR)
    GROUP BY ms.id_inspection
),
-- Discount-invoice aggregation (the "discount invoice" table), joined via uuid_inspection per
-- decisions.md. Feeds the cost model's discount term and the fallback-attribution health metric:
-- a REVIEW-checkpoint discount can fully exempt the charge independent of Lia's own negotiation.
invoice_discount_agg AS (
    SELECT
        idisc.uuid_inspection,
        BOOL_OR(idisc.id_checkpoint = 'REVIEW') AS has_fallback_review_discount
    FROM datalake_inspection_services_clean.invoice_discount idisc
    GROUP BY idisc.uuid_inspection
),
-- Whether the inspection actually reached human contestation analysis (AC), sourced from the
-- CDP event create_offboarding_contestation_analysis — distinct from the base OBT's
-- ts_sent_to_contestation_analysis, which fires as soon as a case is routed toward AC/Lia,
-- before Lia's own negotiation (and possible tenant agreement) plays out. Instrumented reliably
-- since at least March 2026; see OBT Property Integrity.md Caveats.
human_contestation_analysis_cdp AS (
    SELECT
        get_json_object(event_properties, '$.inspectionUuid') AS uuid_inspection,
        MIN(ts_event) AS ts_human_contestation_analysis
    FROM datalake_cdp_clean.transactional
    WHERE event_name = 'create_offboarding_contestation_analysis'
      AND get_json_object(event_properties, '$.inspectionType') = 'offboarding'
      AND year >= 2024
    GROUP BY 1
)
SELECT
    CASE
        WHEN annotation_auto_pricing.ts_created >= c.AUTO_PRICING_ROLLOUT_START
             AND annotation_auto_pricing.value IN ('success', 'failed')
            THEN 'variant_auto_pricing'
        WHEN annotation_auto_pricing.ts_created >= c.AUTO_PRICING_ROLLOUT_START
             AND annotation_auto_pricing.value = 'control'
            THEN 'controlgroup_auto_pricing'
        ELSE NULL
    END AS auto_pricing_group,
    CASE
        WHEN annotation_auto_pricing.ts_created >= c.AUTO_PRICING_ROLLOUT_START
            THEN annotation_auto_pricing.value
        ELSE NULL
    END AS auto_pricing_result,
    CASE
        WHEN LOWER(annotation_timeline.value) = 'true' THEN 'Native'
        ELSE 'PWA'
    END AS user_experience_flow,
    CASE
        WHEN LOWER(annotation_second_review.value) = 'true' THEN 'Native'
        ELSE 'PWA'
    END AS dispute_overview_flow,
    CASE
        WHEN LOWER(annotation_first_review.value) = 'true' THEN 'Native'
        ELSE 'PWA'
    END AS first_review_tenant_flow,
    CAST(annotation_kirk.value AS BOOLEAN)          AS is_kirk_test,
    CAST(annotation_eviction_kirk.value AS BOOLEAN) AS is_eviction_kirk_test,
    CASE
        WHEN kirk.id_inspection IS NOT NULL THEN COALESCE(kirk.analysis_mode, 'DEFAULT')
    END AS kirk_analysis_mode,
    annotation_mediation.value AS conversational_mediation_group,
    annotation_mediation.ts_created AS ts_conversational_mediation_assigned,
    CASE
        WHEN obt.has_mediation_ticket = TRUE
         AND (
              obt.has_early_mediation = TRUE
              OR (
                  obt.ts_budget_approval_sent_to_owner IS NOT NULL
                  AND (
                      (obt.has_tenant_approved_budget_approval = TRUE  AND obt.has_owner_approved_budget_approval IS NULL)
                      OR (obt.has_tenant_approved_budget_approval IS NULL AND obt.has_owner_approved_budget_approval = TRUE)
                      OR (obt.has_tenant_approved_budget_approval IS NULL AND obt.has_owner_approved_budget_approval IS NULL)
                  )
              )
         )
        THEN TRUE
        ELSE FALSE
    END AS mediation_due_to_lack_of_response,
    CASE
        WHEN obt.has_mediation_ticket = TRUE
         AND obt.has_early_mediation = FALSE
         AND obt.ts_budget_approval_sent_to_owner IS NOT NULL
         AND (
             obt.has_tenant_approved_budget_approval = FALSE
             OR obt.has_owner_approved_budget_approval = FALSE
         )
        THEN TRUE
        ELSE FALSE
    END AS mediation_due_to_disagreement,
    COALESCE(tcm.has_tenant_contestation_media, FALSE) AS has_tenant_contestation_media,
    -- Domain target metric (2026-07-29 strategy pivot): any customer dispute on the
    -- termination, tenant- or owner-side. See strategy.md and metrics/dispute-rate.md.
    (COALESCE(obt.total_tenant_contestation, 0) > 0 OR COALESCE(obt.repairs_added_by_owner_review, 0) > 0) AS has_disputes,
    arcr.total_ar_cost_contested_repairs,
    -- Lia engagement: row exists at all = agent attempted contact; among rows, is_completed = true
    -- AND is_tenant_agreed IS NULL = ran to completion with no explicit tenant response.
    (lia.id_inspection IS NOT NULL) AS has_lia_mediation_record,
    CAST(lia.is_completed AS BOOLEAN) AS lia_mediation_is_completed,
    CAST(lia.is_tenant_agreed AS BOOLEAN) AS lia_mediation_is_tenant_agreed,
    CAST(lia.applied_discount_amount AS DOUBLE) AS lia_applied_discount_amount,
    CAST(lia.ts_completed AS TIMESTAMP) AS lia_ts_completed,
    CASE
        WHEN lia.id_inspection IS NULL THEN NULL
        WHEN CAST(lia.is_tenant_agreed AS BOOLEAN) = TRUE THEN 'Conversa ativa'
        WHEN lia.is_completed IS NULL THEN
            CASE WHEN f.has_human_message_any = 1 THEN 'Conversa ativa' ELSE NULL END
        WHEN f.has_human_message_before_timeout = 1 THEN 'Conversa ativa'
        WHEN f.has_human_message_any = 1 THEN 'Resposta tardia'
        ELSE 'Sem resposta'
    END AS lia_conversation_interaction_category,
    COALESCE(idisc.has_fallback_review_discount, FALSE) AS has_fallback_review_discount,
    COALESCE(hca.uuid_inspection IS NOT NULL, FALSE) AS has_human_contestation_analysis,
    CAST(hca.ts_human_contestation_analysis AS TIMESTAMP) AS ts_human_contestation_analysis,

    -- Maturation: resolved (early/compulsory/discount agreement, via the base OBT's has_agreement)
    -- OR sent to AC, as a binary flag over all test+control entrants (in-flight cases stay FALSE).
    (obt.ts_sent_to_contestation_analysis IS NOT NULL) AS is_lia_matured,
    -- Best-effort single "matured at" timestamp for the elapsed-time metric: whichever resolution
    -- signal fired for that row. Caveat: no first-class "resolved_at" column exists yet upstream
    -- (see OBT Property Integrity.md Caveats) — this COALESCEs the closest proxies.
    COALESCE(obt.ts_reviewed, obt.ts_budget_approval, obt.ts_sent_to_contestation_analysis) AS ts_lia_matured,
    obt.sk_contract,
    obt.sk_house,
    obt.sk_termination,
    obt.sk_inspection,
    obt.sk_assessment,
    obt.sk_client_side,
    obt.is_spoc_test_group_contract,
    obt.is_spoc_eligible,
    obt.is_eviction,
    obt.is_high_value,
    obt.is_exit_inspection_opt_out,
    obt.is_automated_ar,
    obt.no_human_ar,
    obt.rent_value,
    obt.fee_final_amount,
    obt.total_tenant_repair_review_cost,
    obt.total_tenant_repair_review_contestation_cost,
    obt.final_tenant_inspection_cost,
    obt.termination_category,
    obt.termination_status,
    obt.termination_reason,
    obt.abc_variant,
    obt.inspection_status,
    obt.automation_group,
    obt.mediation_squad,
    obt.has_repairs,
    obt.has_tenant_access_review,
    obt.has_owner_access_review,
    obt.has_tenant_approved_review,
    obt.has_owner_approved_review,
    obt.has_tenant_access_budget_approval,
    obt.has_owner_access_budget_approval,
    obt.has_tenant_approved_budget_approval,
    obt.has_owner_approved_budget_approval,
    obt.has_agreement,
    obt.has_early_agreement,
    obt.has_late_agreement,
    obt.has_discount_agreement,
    obt.has_compulsory_agreement,
    obt.has_mediation_ticket,
    obt.has_early_mediation,
    obt.total_repairs_requested,
    obt.repairs_added_by_5a_review,
    obt.repairs_added_by_owner_review,
    obt.total_unset_repairs,
    obt.repairs_exempted_in_ar,
    obt.total_tentant_repair_ar,
    obt.repairs_exempted_by_owner_review,
    obt.total_tentant_repair_review,
    obt.total_tenant_contestation,
    obt.repairs_exempted_ac,
    obt.repairs_absorbed_ac,
    obt.total_tentant_repair_ac,
    obt.total_repairs_final_report,
    obt.checkpoint_journey,
    obt.model_discount_type,
    obt.discount_value_type,
    obt.discount_stage,
    obt.has_discount_try,
    obt.is_discount_accepted,
    obt.invoice_discount_value,
    obt.leadtime_total,
    obt.leadtime_vt,
    obt.leadtime_vt_to_ar,
    obt.leadtime_ar,
    obt.leadtime_owner_tenant_review,
    obt.leadtime_ac,
    obt.leadtime_budget_approval,
    obt.leadtime_mediation,
    obt.ts_termination_request,
    obt.dt_ended_rental_confirmed,
    obt.ts_inspected,
    obt.dt_termination,
    obt.ts_automatic_repair_processing,
    obt.ts_sent_to_repair_analysis,
    obt.ts_sent_to_owner_review,
    obt.ts_review_started_by_owner,
    obt.ts_sent_to_tenant_review,
    obt.ts_review_started_by_tenant,
    obt.ts_sent_to_contestation_analysis,
    obt.ts_contestation_analysis_finished,
    obt.ts_budget_approval,
    obt.ts_budget_approval_sent_to_owner,
    obt.ts_budget_approval_started_by_owner,
    obt.ts_budget_approval_sent_to_tenant,
    obt.ts_budget_approval_started_by_tenant,
    obt.ts_reviewed,
    obt.dt_discount_invoice_creation,
    obt.dt_mediation_started,
    obt.ts_termination_finished
FROM dw_offboarding.obt_offboarding obt
CROSS JOIN constants c
LEFT JOIN deduped_annotations annotation_timeline
    ON obt.sk_client_side = annotation_timeline.uuid_inspection
   AND annotation_timeline.key = c.TIMELINE_KEY
   AND annotation_timeline.row_num = 1
LEFT JOIN deduped_annotations annotation_second_review
    ON obt.sk_client_side = annotation_second_review.uuid_inspection
   AND annotation_second_review.key = c.DISPUTE_OVERVIEW_KEY
   AND annotation_second_review.row_num = 1
LEFT JOIN deduped_annotations annotation_first_review
    ON obt.sk_client_side = annotation_first_review.uuid_inspection
   AND annotation_first_review.key = c.NATIVE_FIRST_REVIEW
   AND annotation_first_review.row_num = 1
LEFT JOIN deduped_annotations annotation_kirk
    ON obt.sk_client_side = annotation_kirk.uuid_inspection
   AND annotation_kirk.key = c.KIRK_TEST_KEY
   AND annotation_kirk.row_num = 1
LEFT JOIN deduped_annotations annotation_eviction_kirk
    ON obt.sk_client_side = annotation_eviction_kirk.uuid_inspection
   AND annotation_eviction_kirk.key = c.EVICTION_KIRK_TEST_KEY
   AND annotation_eviction_kirk.row_num = 1
LEFT JOIN kirk_analysis kirk
    ON obt.sk_client_side = kirk.id_inspection
   AND kirk.row_num = 1
LEFT JOIN deduped_annotations annotation_auto_pricing
    ON obt.sk_client_side = annotation_auto_pricing.uuid_inspection
   AND annotation_auto_pricing.key = c.AUTO_PRICING_TEST_KEY
   AND annotation_auto_pricing.row_num = 1
LEFT JOIN deduped_annotations annotation_mediation
    ON obt.sk_client_side = annotation_mediation.uuid_inspection
   AND annotation_mediation.key = c.MEDIATION_TEST_KEY
   AND annotation_mediation.row_num = 1
LEFT JOIN tenant_contestation_media tcm
    ON obt.sk_inspection = tcm.sk_inspection
LEFT JOIN ar_cost_contested_repairs arcr
    ON obt.sk_inspection = arcr.sk_inspection
LEFT JOIN deduped_lia_mediation lia
    ON CAST(obt.sk_inspection AS VARCHAR) = CAST(lia.id_inspection AS VARCHAR)
LEFT JOIN lia_mediation_flags f
    ON CAST(lia.id_inspection AS VARCHAR) = CAST(f.id_inspection AS VARCHAR)
LEFT JOIN invoice_discount_agg idisc
    ON obt.sk_client_side = idisc.uuid_inspection
LEFT JOIN human_contestation_analysis_cdp hca
    ON obt.sk_client_side = hca.uuid_inspection
