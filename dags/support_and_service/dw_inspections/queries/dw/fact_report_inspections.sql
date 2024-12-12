SELECT
    ra.id_inspection AS sk_inspection,
    ra.id_assessment AS sk_assessment,
    ra.id_previous_assessment AS sk_previous_assessment,
    ra.total_cost,
    ra.owner_amount_payment,
    ra.tenant_amount_payment,
    COUNT(rr.id_repair_request) FILTER(WHERE COALESCE(rr.total_tenant_contestation, 0) <> 0) AS total_tenant_contestation,
    COUNT(rr.id_repair_request) FILTER(WHERE COALESCE(rr.total_owner_budget_approval_contestation, 0) <> 0) AS total_owner_budget_approval_contestation,
    COUNT(rr.id_repair_request) FILTER(WHERE COALESCE(rr.total_tenant_budget_approval_contestation, 0) <> 0) AS total_tenant_budget_approval_contestation,
    COUNT(rr.id_repair_request) FILTER(WHERE is_exempted = TRUE) AS total_exemptions,
    COUNT(rr.id_repair_request) FILTER(WHERE is_exempted_by_owner = TRUE) AS total_exemptions_by_owner,
    COUNT(rr.id_repair_request) FILTER(WHERE is_exempted_by_owner_from_budget = TRUE) AS total_exemptions_by_owner_from_budget,
    COUNT(rr.id_repair_request) FILTER(WHERE is_requested_by_owner = TRUE) AS total_repairs_requested_by_owner,
    isa.has_owner_access_review,
    isa.has_tenant_access_review,
    isa.has_owner_access_budget_approval,
    isa.has_tenant_access_budget_approval,
    CASE WHEN ra.approval_type = 'BUDGET_APPROVAL' THEN ra.owner_approved END AS has_owner_approved_budget_approval,
    CASE WHEN ra.approval_type = 'BUDGET_APPROVAL' THEN ra.tenant_approved END AS has_tenant_approved_budget_approval,
    isc.ts_scheduled,
    isc.ts_received,
    isc.ts_processing,
    isc.ts_cancelled,
    isc.ts_sent_to_inspection_editing,
    isc.ts_automatic_repair_processing,
    isc.ts_sent_to_review,
    isc.ts_review_started,
    isc.ts_sent_to_repair_analysis,
    isc.ts_sent_to_owner_review,
    isa.ts_first_owner_access_review,
    isa.ts_last_owner_access_review,
    isc.ts_review_started_by_owner,
    isc.ts_sent_to_tenant_review,
    isa.ts_first_tenant_access_review,
    isa.ts_last_tenant_access_review,
    isc.ts_review_started_by_tenant,
    isc.ts_sent_to_contestation_analysis,
    isc.ts_contestation_analysis_finished,
    isc.ts_budget_approval,
    isc.ts_budget_approval_sent_to_owner,
    isc.ts_budget_approval_started_by_owner,
    isc.ts_budget_approval_sent_to_tenant,
    isc.ts_budget_approval_started_by_tenant,
    isc.ts_reviewed,
    CASE WHEN ra.approval_type = 'BUDGET_APPROVAL' THEN ra.ts_owner_approved END AS ts_owner_approved_budget_approval,
    CASE WHEN ra.approval_type = 'BUDGET_APPROVAL' THEN ra.ts_tenant_approved END AS ts_tenant_approved_budget_approval,
    CASE WHEN ra.approval_type = 'REVIEW' THEN ra.dt_owner_limit_revision END AS ts_owner_limit_revision,
    CASE WHEN ra.approval_type = 'REVIEW' THEN ra.dt_tenant_limit_revision END AS ts_tenant_limit_revision,
    CASE WHEN ra.approval_type = 'BUDGET_APPROVAL' THEN ra.dt_owner_limit_revision END AS ts_owner_limit_revision_budget_approval,
    CASE WHEN ra.approval_type = 'BUDGET_APPROVAL' THEN ra.dt_tenant_limit_revision END AS ts_tenant_limit_revision_budget_approval,
    NOW() AS ts_load,
    ra.year,
    ra.month,
    ra.day
FROM
    datalake_inspections.report_approvals AS ra
LEFT JOIN
    datalake_inspections.repair_request AS rr
      ON ra.id_inspection = rr.id_inspection
LEFT JOIN
    datalake_amplitude_inspections.inspection_stages_access AS isa
        ON ra.id_inspection = isa.id_inspection
LEFT JOIN
    datalake_inspections.inspection_status_change AS isc
        ON ra.id_inspection = isc.id_inspection
WHERE
    MAKE_DATE(ra.year, ra.month, ra.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY
    ALL
