WITH rollout AS (
    SELECT
        ft.sk_contract,
        da.email AS agent_email,
        ROW_NUMBER() OVER (
            PARTITION BY ft.sk_contract
            ORDER BY
                CASE WHEN da.email IS NOT NULL THEN 1 ELSE 2 END ASC,
                ft.ts_termination_request DESC
        ) AS rn
    FROM
        dw_offboarding.fact_terminations AS ft
    LEFT JOIN
        dw_customer_support.dim_analyst AS da
            ON ft.sk_analyst = da.sk_analyst
),
repair_request AS (
    SELECT
        rr.id_contract,
        rr.id_inspection AS sk_inspection,
        MAX(rr.ts_updated) AS ts_updated,
        COUNT(CASE WHEN rr.exempted_on_ar = FALSE AND rr.requester_type IN ('ADMIN', 'INSPECTIONS_SERVICE') THEN 1 END)
            + COUNT(CASE WHEN rr.requester_type = 'OWNER' THEN 1 END)
            - COUNT(CASE WHEN rr.is_exempted_by_owner = TRUE THEN 1 END) AS total_tenant_repair_review
    FROM
        datalake_inspections.repair_request AS rr
    WHERE
        rr.responsibility IN ('TENANT', 'OWNER', 'ABSORBED_BY_COMPANY', 'EXEMPTED')
        AND rr.comment IS NOT NULL
    GROUP BY
        1, 2
),
repair_request_final AS (
    SELECT
        rreq.id_contract,
        rreq.sk_inspection,
        rreq.ts_updated,
        rreq.total_tenant_repair_review,
        ROW_NUMBER() OVER (PARTITION BY rreq.id_contract ORDER BY rreq.ts_updated DESC) AS row
    FROM
        repair_request AS rreq
),
inspections AS (
    SELECT
        fi.sk_contract,
        fi.has_early_mediation,
        fi.ts_updated AS ts_updated_fi,
        fri.has_tenant_approved_review,
        fri.total_tenant_contestation,
        fri.has_owner_approved_review,
        fri.total_repairs_requested_by_owner,
        fri.ts_budget_approval_sent_to_owner,
        fri.has_owner_approved_budget_approval,
        fri.has_tenant_approved_budget_approval,
        rrf.total_tenant_repair_review,
        CASE
            WHEN fri.has_tenant_approved_review IS NULL THEN NULL
            WHEN fri.total_tenant_contestation > 0 THEN FALSE
            WHEN fri.total_tenant_contestation = 0 AND fri.has_tenant_approved_review THEN TRUE
            ELSE FALSE
        END AS has_tenant_approved_review_adjusted,
        CASE
            WHEN fri.has_owner_approved_review IS NULL THEN NULL
            WHEN fri.total_repairs_requested_by_owner > 0 THEN FALSE
            WHEN fri.total_repairs_requested_by_owner = 0 AND fri.has_owner_approved_review THEN TRUE
            ELSE FALSE
        END AS has_owner_approved_review_adjusted,
        CASE
            WHEN fri.ts_budget_approval_sent_to_owner IS NOT NULL
                AND fri.has_owner_approved_budget_approval = TRUE
                AND fri.has_tenant_approved_budget_approval = FALSE
                THEN 'owner_approval_and_tenant_disapproval'
            WHEN fri.ts_budget_approval_sent_to_owner IS NOT NULL
                AND fri.has_owner_approved_budget_approval = TRUE
                AND fri.has_tenant_approved_budget_approval IS NULL
                THEN 'owner_approval_and_tenant_no_answer'
            WHEN fri.ts_budget_approval_sent_to_owner IS NOT NULL
                AND fri.has_owner_approved_budget_approval = FALSE
                AND fri.has_tenant_approved_budget_approval IS NULL
                THEN 'owner_disapproval_and_tenant_no_answer'
            WHEN fri.ts_budget_approval_sent_to_owner IS NOT NULL
                AND fri.has_owner_approved_budget_approval = FALSE
                AND fri.has_tenant_approved_budget_approval = TRUE
                THEN 'tenant_approval_and_owner_disapproval'
            WHEN fri.ts_budget_approval_sent_to_owner IS NOT NULL
                AND fri.has_owner_approved_budget_approval IS NULL
                AND fri.has_tenant_approved_budget_approval = TRUE
                THEN 'tenant_approval_and_owner_no_answer'
            WHEN fri.ts_budget_approval_sent_to_owner IS NOT NULL
                AND fri.has_owner_approved_budget_approval IS NULL
                AND fri.has_tenant_approved_budget_approval = FALSE
                THEN 'tenant_disapproval_and_owner_no_answer'
            WHEN fri.ts_budget_approval_sent_to_owner IS NOT NULL
                AND fri.has_owner_approved_budget_approval = TRUE
                AND fri.has_tenant_approved_budget_approval = TRUE
                THEN 'both_approved'
            WHEN fri.ts_budget_approval_sent_to_owner IS NOT NULL
                AND fri.has_owner_approved_budget_approval = FALSE
                AND fri.has_tenant_approved_budget_approval = FALSE
                THEN 'both_disapproved'
            WHEN fri.ts_budget_approval_sent_to_owner IS NOT NULL
                AND fri.has_owner_approved_budget_approval IS NULL
                AND fri.has_tenant_approved_budget_approval IS NULL
                THEN 'both_no_answer'
            WHEN fi.has_early_mediation = TRUE THEN NULL
            ELSE 'no_budget'
        END AS budget_approval_response_status,
        ROW_NUMBER() OVER (PARTITION BY fi.sk_contract ORDER BY fi.ts_updated DESC) AS rn
    FROM
        dw_inspections.fact_inspection AS fi
    LEFT JOIN
        dw_inspections.dim_inspection AS di
            ON fi.sk_inspection = di.sk_inspection
    LEFT JOIN
        dw_inspections.fact_report_inspections AS fri
            ON fi.sk_inspection = CAST(fri.sk_inspection AS STRING)
    LEFT JOIN
        repair_request_final AS rrf
            ON fi.sk_inspection = CAST(rrf.sk_inspection AS STRING)
            AND rrf.row = 1
    WHERE
        di.inspection_type = 'offboarding'
),
inspections_adjusted AS (
    SELECT
        sk_contract,
        rn,
        budget_approval_response_status,
        CASE
            WHEN total_tenant_repair_review > 0
                AND has_owner_approved_review_adjusted = TRUE
                AND has_tenant_approved_review_adjusted = FALSE
                THEN 'owner_approval_and_tenant_disapproval'
            WHEN total_tenant_repair_review > 0
                AND has_owner_approved_review_adjusted = TRUE
                AND has_tenant_approved_review_adjusted IS NULL
                THEN 'owner_approval_and_tenant_no_answer'
            WHEN total_tenant_repair_review > 0
                AND has_owner_approved_review_adjusted = FALSE
                AND has_tenant_approved_review_adjusted IS NULL
                THEN 'owner_disapproval_and_tenant_no_answer'
            WHEN total_tenant_repair_review > 0
                AND has_owner_approved_review_adjusted = FALSE
                AND has_tenant_approved_review_adjusted = TRUE
                THEN 'tenant_approval_and_owner_disapproval'
            WHEN total_tenant_repair_review > 0
                AND has_owner_approved_review_adjusted IS NULL
                AND has_tenant_approved_review_adjusted = TRUE
                THEN 'tenant_approval_and_owner_no_answer'
            WHEN total_tenant_repair_review > 0
                AND has_owner_approved_review_adjusted IS NULL
                AND has_tenant_approved_review_adjusted = FALSE
                THEN 'tenant_disapproval_and_owner_no_answer'
            WHEN total_tenant_repair_review > 0
                AND has_owner_approved_review_adjusted = TRUE
                AND has_tenant_approved_review_adjusted = TRUE
                THEN 'both_approved'
            WHEN total_tenant_repair_review > 0
                AND has_owner_approved_review_adjusted = FALSE
                AND has_tenant_approved_review_adjusted = FALSE
                THEN 'both_disapproved'
            WHEN total_tenant_repair_review > 0
                AND has_owner_approved_review_adjusted IS NULL
                AND has_tenant_approved_review_adjusted IS NULL
                THEN 'both_no_answer'
            ELSE 'no_review'
        END AS review_response_status
    FROM
        inspections
),
owner_pp_multi AS (
    SELECT
        lrf.sk_contract,
        CASE
            WHEN doh.is_pp_multi_active = TRUE
                OR doh.ongoing_houses >= 5
                THEN TRUE
            ELSE FALSE
        END AS is_pp_multi,
        ROW_NUMBER() OVER (
            PARTITION BY lrf.sk_contract
            ORDER BY doh.dt_houses_owned DESC
        ) AS rn
    FROM
        datalake_pro_owners.daily_owner_houses_quantity_history AS doh
    LEFT JOIN
        dw_rent.fact_listing_rent_flows AS lrf
            ON lrf.sk_owner = doh.id_owner
    WHERE
        lrf.sk_contract > 0
),
obt AS (
    SELECT
        obt.sk_contract AS id_contract,
        rol.agent_email,
        CASE
            WHEN obt.ts_termination_finished IS NOT NULL OR obt.termination_status = 'ended' THEN 'TF'
            WHEN obt.ts_reviewed IS NOT NULL THEN 'mediation'
            WHEN obt.ts_budget_approval_sent_to_tenant IS NOT NULL THEN 'budget_approval_iq'
            WHEN obt.ts_budget_approval_sent_to_owner IS NOT NULL THEN 'budget_approval_pp'
            WHEN obt.ts_sent_to_contestation_analysis IS NOT NULL THEN 'contest_an'
            WHEN obt.ts_sent_to_tenant_review IS NOT NULL THEN 'report_comments_iq'
            WHEN obt.ts_sent_to_owner_review IS NOT NULL THEN 'report_comments_pp'
            WHEN obt.ts_inspected IS NOT NULL THEN 'repair_an'
            WHEN obt.dt_termination < DATE(CURRENT_DATE) THEN 'inspection'
            WHEN obt.dt_termination >= DATE(CURRENT_DATE) THEN 'pre_saida'
            ELSE NULL
        END AS wip_stage,
        obt.ts_termination_request,
        DATE(obt.dt_termination) AS dt_termination,
        DATE(obt.ts_inspected) AS dt_inspected,
        obt.is_exit_inspection_opt_out,
        DATE(obt.ts_sent_to_repair_analysis) AS dt_repair_analysis_started,
        DATE(obt.ts_sent_to_owner_review) AS dt_repair_analysis_finished,
        DATE(obt.ts_sent_to_owner_review) AS dt_owner_engagement_started,
        DATE(obt.ts_sent_to_tenant_review) AS dt_tenant_engagement_started,
        DATE(obt.ts_sent_to_tenant_review) AS dt_owner_engagement_finished,
        DATE(COALESCE(obt.ts_sent_to_contestation_analysis, obt.ts_reviewed)) AS dt_tenant_engagement_finished,
        DATE(obt.ts_sent_to_contestation_analysis) AS dt_contestation_analysis_started,
        DATE(obt.ts_contestation_analysis_finished) AS dt_contestation_analysis_finished,
        DATE(obt.ts_budget_approval_sent_to_owner) AS dt_owner_budget_approval_started,
        DATE(obt.ts_budget_approval_sent_to_tenant) AS dt_tenant_budget_approval_started,
        DATE(obt.ts_budget_approval_sent_to_tenant) AS dt_owner_budget_approval_finished,
        DATE(obt.ts_reviewed) AS dt_tenant_budget_approval_finished,
        DATE(obt.ts_reviewed) AS dt_budget_approval_finished,
        DATE(obt.dt_mediation_started) AS dt_mediation_started,
        DATE(obt.ts_termination_finished) AS dt_termination_finished,
        obt.is_spoc_test_group_contract,
        obt.termination_status,
        obt.final_tenant_inspection_cost,
        obt.has_early_agreement AS is_early_both_agree,
        obt.has_repairs,
        obt.has_agreement,
        CASE WHEN obt.model_discount_type = 'AUTOMATIC_BANDAID' THEN TRUE ELSE FALSE END AS has_automatic_bandaid,
        COALESCE(pm.is_pp_multi, FALSE) AS is_pp_multi,
        obt.leadtime_total,
        ia.review_response_status,
        ia.budget_approval_response_status
    FROM
        dw_offboarding.obt_offboarding AS obt
    LEFT JOIN (
        SELECT
            sk_contract,
            agent_email,
            rn
        FROM
            rollout
        WHERE
            rn = 1
    ) AS rol
        ON obt.sk_contract = rol.sk_contract
    LEFT JOIN
        inspections_adjusted AS ia
            ON obt.sk_contract = ia.sk_contract
            AND ia.rn = 1
    LEFT JOIN
        owner_pp_multi AS pm
            ON obt.sk_contract = pm.sk_contract
            AND pm.rn = 1
    WHERE
        obt.is_spoc_test_group_contract = TRUE
        AND obt.has_mediation_ticket = TRUE
        AND DATE(obt.ts_termination_request) >= DATE('2024-01-01')
        AND obt.termination_status NOT IN ('CANCELED', 'canceled')
)
SELECT
    id_contract,
    agent_email,
    wip_stage,
    ts_termination_request,
    dt_termination,
    dt_inspected,
    is_exit_inspection_opt_out,
    dt_repair_analysis_started,
    dt_repair_analysis_finished,
    dt_owner_engagement_started,
    dt_tenant_engagement_started,
    dt_owner_engagement_finished,
    dt_tenant_engagement_finished,
    dt_contestation_analysis_started,
    dt_contestation_analysis_finished,
    dt_owner_budget_approval_started,
    dt_tenant_budget_approval_started,
    dt_owner_budget_approval_finished,
    dt_tenant_budget_approval_finished,
    dt_budget_approval_finished,
    dt_mediation_started,
    dt_termination_finished,
    is_spoc_test_group_contract,
    termination_status,
    final_tenant_inspection_cost,
    is_early_both_agree,
    has_repairs,
    has_agreement,
    has_automatic_bandaid,
    is_pp_multi,
    leadtime_total,
    review_response_status,
    budget_approval_response_status,
    CASE
        WHEN COALESCE(is_exit_inspection_opt_out, FALSE) = TRUE THEN NULL
        WHEN dt_termination IS NOT NULL
            THEN GREATEST(0, DATEDIFF(COALESCE(dt_inspected, CURRENT_DATE), dt_termination))
    END AS leadtime_inspection,
    CASE
        WHEN COALESCE(dt_repair_analysis_started, dt_inspected) IS NOT NULL
            THEN DATEDIFF(
                COALESCE(dt_repair_analysis_finished, CURRENT_DATE),
                COALESCE(dt_repair_analysis_started, dt_inspected)
            )
    END AS leadtime_repair_analysis,
    CASE
        WHEN COALESCE(dt_owner_engagement_started, dt_repair_analysis_finished) IS NOT NULL
            THEN DATEDIFF(
                COALESCE(dt_tenant_engagement_started, dt_termination_finished, CURRENT_DATE),
                COALESCE(dt_owner_engagement_started, dt_repair_analysis_finished)
            )
    END AS leadtime_owner_engagement,
    CASE
        WHEN dt_tenant_engagement_started IS NOT NULL
            THEN DATEDIFF(COALESCE(dt_contestation_analysis_started, CURRENT_DATE), dt_tenant_engagement_started)
    END AS leadtime_tenant_engagement,
    CASE
        WHEN dt_contestation_analysis_started IS NOT NULL
            THEN DATEDIFF(COALESCE(dt_owner_budget_approval_started, CURRENT_DATE), dt_contestation_analysis_started)
    END AS leadtime_contestation_analysis,
    CASE
        WHEN dt_owner_budget_approval_started IS NOT NULL
            THEN DATEDIFF(COALESCE(dt_tenant_budget_approval_started, CURRENT_DATE), dt_owner_budget_approval_started)
    END AS leadtime_owner_budget_approval,
    CASE
        WHEN dt_tenant_budget_approval_started IS NOT NULL
            THEN DATEDIFF(COALESCE(dt_budget_approval_finished, CURRENT_DATE), dt_tenant_budget_approval_started)
    END AS leadtime_tenant_budget_approval,
    CASE
        WHEN dt_mediation_started IS NOT NULL
            THEN DATEDIFF(COALESCE(dt_termination_finished, CURRENT_DATE), dt_mediation_started)
    END AS leadtime_mediation,
    CASE
        WHEN dt_termination_finished IS NULL
            THEN DATEDIFF(CURRENT_DATE, COALESCE(ts_termination_request, dt_termination))
    END AS aging,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM
    obt