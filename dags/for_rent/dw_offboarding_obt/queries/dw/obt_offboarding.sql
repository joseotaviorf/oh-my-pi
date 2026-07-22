WITH
  auto_pricing_annotations AS (
    SELECT
      an.uuid_inspection,
      an.value AS auto_pricing_result,
      ROW_NUMBER() OVER (
        PARTITION BY an.uuid_inspection
        ORDER BY an.ts_created DESC
      ) AS rni_pricing
    FROM
      datalake_inspection_services_clean.annotation AS an
    WHERE
      an.key = 'automatic-repair-pricing'
      AND an.ts_created >= TIMESTAMP '2026-05-18 00:00:00 UTC'
  ),
  inspections AS (
    SELECT 
      -- Ids:
      fi.sk_inspection,
      fi.sk_assessment,
      fi.sk_contract,
      fi.sk_client_side,
      fi.sk_house,
      -- Categories:
      an.value AS abc_variant,
      di.status AS inspection_status,
      CAST(di.repair_request_ai_flow AS BOOLEAN) AS is_automated_ar,
      di.ai_repair_analysis_control_group AS automation_group,
      ap.auto_pricing_result,
      --Values:
      fri.total_cost,
      -- Flags: 
      fri.has_tenant_access_review,
      fri.has_owner_access_review,
      fri.has_tenant_approved_review,
      fri.has_owner_approved_review,
      fri.has_tenant_access_budget_approval,
      fri.has_owner_access_budget_approval,
      fri.has_tenant_approved_budget_approval,
      fri.has_owner_approved_budget_approval,
      fri.has_agreement, 
      fri.has_early_agreement,
      fri.has_late_agreement, 
      fri.has_discount_agreement,
      fri.has_compulsory_agreement,
      -- Other flags:
      fi.has_early_mediation,
      -- Dates:
      fi.ts_inspected,
      fri.ts_automatic_repair_processing,
      fri.ts_sent_to_repair_analysis,
      fri.ts_sent_to_owner_review,
      fri.ts_review_started_by_owner,
      fri.ts_sent_to_tenant_review,
      fri.ts_review_started_by_tenant,
      fri.ts_sent_to_contestation_analysis,
      fri.ts_contestation_analysis_finished,
      fri.ts_budget_approval,
      fri.ts_budget_approval_sent_to_owner,
      fri.ts_budget_approval_started_by_owner,
      fri.ts_budget_approval_sent_to_tenant,
      fri.ts_budget_approval_started_by_tenant,
      fri.ts_reviewed,
      ROW_NUMBER() OVER(PARTITION BY fi.sk_contract ORDER BY CASE WHEN di.status = 'cancelled' THEN 1 ELSE 0 END ASC, fi.ts_updated DESC) AS rni
    FROM 
      dw_inspections.fact_inspection AS fi
    LEFT JOIN 
      dw_inspections.dim_inspection AS di 
        ON fi.sk_inspection = di.sk_inspection
    LEFT JOIN 
      dw_inspections.fact_report_inspections AS fri
        ON fi.sk_inspection = CAST(fri.sk_inspection AS VARCHAR(10))
		LEFT JOIN
			datalake_inspection_services_clean.annotation AS an 
				ON fi.sk_client_side = an.uuid_inspection
					AND an.key = 'single-clear-journey'
    LEFT JOIN
      auto_pricing_annotations AS ap
        ON fi.sk_client_side = ap.uuid_inspection
        AND ap.rni_pricing = 1
    WHERE TRUE
      AND di.inspection_type = 'offboarding'
  )
SELECT DISTINCT
    --Ids: 
    ft.sk_contract,
    ft.sk_house,
    ft.sk_termination,
    i.sk_inspection,
    i.sk_assessment,
    i.sk_client_side,
    --Id flags:
    COALESCE(ft.is_spoc_contract, FALSE) AND NOT COALESCE(ft.is_spoc_control_group, FALSE) AS is_spoc_contract,
    ft.is_spoc_eligible,
    COALESCE((dt.reason = 'EVICTION'), FALSE) AS is_eviction,
    dc.rent >= 2500 AS is_high_value,
    ft.is_exit_inspection_opt_out,
    i.is_automated_ar,
    CASE
        WHEN i.ts_inspected IS NULL
            THEN NULL
        WHEN COALESCE(ft.total_tentant_repair_ar, 0) = 0
            THEN TRUE
        WHEN COALESCE(i.is_automated_ar, FALSE)
         AND i.auto_pricing_result = 'success'
            THEN TRUE
        ELSE FALSE
    END AS no_human_ar,
    --Values:
    dc.rent AS rent_value,
    ft.fee_final_amount,
    ft.total_tenant_repair_review_cost,
    ft.total_tenant_repair_review_contestation_cost,
    i.total_cost AS final_tenant_inspection_cost,
    --Categories:
    dt.category AS termination_category,
    dt.status AS termination_status,
    dt.reason AS termination_reason,
    i.abc_variant,
    i.inspection_status,
    i.automation_group,
    m.squad AS mediation_squad,
    --Report inspection flags:
    ft.has_repairs,
    i.has_tenant_access_review,
    i.has_owner_access_review,
    i.has_tenant_approved_review,
    i.has_owner_approved_review,
    i.has_tenant_access_budget_approval,
    i.has_owner_access_budget_approval,
    i.has_tenant_approved_budget_approval,
    i.has_owner_approved_budget_approval,
    i.has_agreement, 
    i.has_early_agreement,
    i.has_late_agreement, 
    i.has_discount_agreement,
    i.has_compulsory_agreement,
    dt.has_mediation_ticket,
    i.has_early_mediation,
    --Repairs:
    ft.total_repairs_requested,
    ft.repairs_added_by_5a_review,
    ft.repairs_added_by_owner_review,
    ft.total_unset_repairs,
    ft.repairs_exempted_in_ar,
    ft.total_tentant_repair_ar,
    ft.repairs_exempted_by_owner_review,
    ft.total_tentant_repair_review,
    ft.total_tenant_contestation,
    ft.repairs_exempted_ac,
    ft.repairs_absorbed_ac,
    ft.total_tentant_repair_ac,
    COALESCE(IF(i.has_early_mediation OR i.has_early_agreement, ft.total_tentant_repair_review, ft.total_tentant_repair_ac), 0) AS total_repairs_final_report,
    --Discounts:
    ad.id_checkpoint AS checkpoint_journey,
    ad.model_discount_type,
    ad.discount_value_type,
    ad.discount_stage,
    ad.has_discount_try,
    ad.is_discount_accepted,
    ad.invoice_discount_value,
    --Leadtimes:
    DATE_DIFF(DAY, dd.date, ft.ts_termination_finished) AS leadtime_total,
    DATE_DIFF(DAY, dd.date, i.ts_inspected) AS leadtime_vt,
    DATE_DIFF(DAY, i.ts_inspected, i.ts_sent_to_repair_analysis) AS leadtime_vt_to_ar,
    DATE_DIFF(DAY, i.ts_sent_to_repair_analysis, i.ts_sent_to_owner_review) AS leadtime_ar,
    DATE_DIFF(DAY, i.ts_sent_to_owner_review, COALESCE(i.ts_sent_to_contestation_analysis, i.ts_reviewed)) AS leadtime_owner_tenant_review,
    DATE_DIFF(DAY, i.ts_sent_to_contestation_analysis, i.ts_contestation_analysis_finished) AS leadtime_ac,
    DATE_DIFF(DAY, i.ts_budget_approval_sent_to_owner, i.ts_reviewed) AS leadtime_budget_approval,
    IF(DATE_DIFF(DAY, m.dt_mediation, m.ts_termination_finished) < 0, 0, DATE_DIFF(DAY, m.dt_mediation, m.ts_termination_finished)) AS leadtime_mediation,
    --Dates:
    ft.ts_termination_request,
    dc.dt_ended_rental_confirmed,
    i.ts_inspected,
    dd.date AS dt_termination,
    i.ts_automatic_repair_processing,
    i.ts_sent_to_repair_analysis,
    i.ts_sent_to_owner_review,
    i.ts_review_started_by_owner,
    i.ts_sent_to_tenant_review,
    i.ts_review_started_by_tenant,
    i.ts_sent_to_contestation_analysis,
    i.ts_contestation_analysis_finished,
    i.ts_budget_approval,
    i.ts_budget_approval_sent_to_owner,
    i.ts_budget_approval_started_by_owner,
    i.ts_budget_approval_sent_to_tenant,
    i.ts_budget_approval_started_by_tenant,
    i.ts_reviewed,
    ad.dt_invoice_creation AS dt_discount_invoice_creation,
    m.dt_mediation AS dt_mediation_started,
    ft.ts_termination_finished
FROM 
    dw_offboarding.fact_terminations AS ft 
JOIN 
    dw_offboarding.dim_termination AS dt
        ON ft.sk_termination = dt.sk_termination
JOIN 
    dw_rent.dim_contract AS dc 
        ON ft.sk_contract = dc.sk_contract
LEFT JOIN 
    inspections AS i
        ON ft.sk_contract = i.sk_contract
        AND i.rni = 1
LEFT JOIN 
    datalake_offboarding.mediations AS m
        ON ft.sk_contract = m.id_contract
        AND ft.sk_termination = m.id_termination -- avoid duplicates
LEFT JOIN 
    datalake_inspections.automatic_discounts AS ad
        ON i.sk_client_side = ad.uuid_inspection
LEFT JOIN 
    dw_public.dim_date AS dd 
        ON ft.sk_termination_date = dd.sk_date
WHERE 
    dt.status <> 'CANCELED'
    AND ft.year >= 2024