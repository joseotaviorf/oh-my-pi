WITH 
  assessment AS (
    SELECT
        a.id_assessment,
        a.id_previous_assessment,
        a.id_inspection,
        a.dt_owner_limit_revision,
        a.dt_tenant_limit_revision
    FROM
        datalake_inspection_services_clean.assessment AS a
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY a.id_inspection ORDER BY a.ts_updated DESC) = 1
  ),
  last_review_response as (
    SELECT
      id_inspection,
      reviewer_type,
      is_approved,
      ts_approved
    FROM
      datalake_inspections.reviewer
    WHERE
      approval_type = 'REVIEW'
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id_inspection, reviewer_type ORDER BY ts_approved DESC) = 1
  ),
  last_budget_approval_response as (
    SELECT
      id_inspection,
      reviewer_type,
      is_approved,
      ts_approved
    FROM
      datalake_inspections.reviewer
    WHERE
      approval_type = 'BUDGET_APPROVAL'
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id_inspection, reviewer_type ORDER BY ts_approved DESC) = 1
  ),
  reviewer_approvals AS (
    SELECT
      id_inspection,
      MAX(
        CASE
          WHEN reviewer_type = 'OWNER' AND lr.is_approved IS NOT NULL THEN is_approved
          ELSE NULL
        END
      ) AS has_owner_approved_review,
      MAX(
        CASE
          WHEN reviewer_type = 'TENANT' AND lr.is_approved IS NOT NULL THEN is_approved
          ELSE NULL
        END
      ) AS has_tenant_approved_review,
      MAX(IF(reviewer_type = 'OWNER' AND lr.is_approved, ts_approved, NULL)) AS ts_owner_approved_review,
      MAX(IF(reviewer_type = 'TENANT' AND lr.is_approved, ts_approved, NULL)) AS ts_tenant_approved_review
    FROM
      last_review_response AS lr
    GROUP BY
      id_inspection
  ),
  budget_approvals AS (
    SELECT
      id_inspection,
      MAX(
        CASE
          WHEN reviewer_type = 'OWNER' AND lr.is_approved IS NOT NULL THEN is_approved
          ELSE NULL
        END
      ) AS has_owner_approved_budget_approval,
      MAX(
        CASE
          WHEN reviewer_type = 'TENANT' AND lr.is_approved IS NOT NULL THEN is_approved
          ELSE NULL
        END
      ) AS has_tenant_approved_budget_approval,
      MAX(IF(reviewer_type = 'OWNER' AND lr.is_approved, ts_approved, NULL)) AS ts_owner_approved_budget_approval,
      MAX(IF(reviewer_type = 'TENANT' AND lr.is_approved, ts_approved, NULL)) AS ts_tenant_approved_budget_approval
    FROM
      last_budget_approval_response AS lr
    GROUP BY
      id_inspection
  ),
  union_approvals AS (
    SELECT
      COALESCE(ra.id_inspection, ba.id_inspection) AS id_inspection,
      ra.has_owner_approved_review,
      ra.has_tenant_approved_review,
      ba.has_owner_approved_budget_approval,
      ba.has_tenant_approved_budget_approval,
      ra.ts_owner_approved_review,
      ra.ts_tenant_approved_review,
      ba.ts_owner_approved_budget_approval,
      ba.ts_tenant_approved_budget_approval
    FROM 
      reviewer_approvals AS ra
    FULL OUTER JOIN 
      budget_approvals AS ba
        ON ra.id_inspection = ba.id_inspection
  ),
  db_approvals AS (
    SELECT 
      u.id_inspection,
      b.total_cost,
      b.owner_amount_payment,
      b.tenant_amount_payment,
      CAST(i.has_agreement AS BOOLEAN) AS has_agreement,
      b.is_early_both_agree AS has_early_agreement,
      CAST(i.has_late_agreement AS BOOLEAN) AS has_late_agreement,
      u.has_owner_approved_review,
      u.has_tenant_approved_review,
      u.has_owner_approved_budget_approval,
      u.has_tenant_approved_budget_approval,
      u.ts_owner_approved_review,
      u.ts_tenant_approved_review,
      u.ts_owner_approved_budget_approval,
      u.ts_tenant_approved_budget_approval,
      b.dt_owner_dead_line,
      b.dt_tenant_dead_line
    FROM 
      union_approvals AS u
    LEFT JOIN 
      datalake_inspection_services_clean.budget AS b
        ON u.id_inspection = b.id_inspection
    LEFT JOIN 
      datalake_inspection_services_clean.inspection AS i
        ON u.id_inspection = i.id_inspection
  )
SELECT
  isa.id_inspection AS sk_inspection,
  a.id_assessment AS sk_assessment,
  a.id_previous_assessment AS sk_previous_assessment,
  da.total_cost,
  da.owner_amount_payment,
  da.tenant_amount_payment,
  ad.discount_reviewed_value,
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
  da.has_agreement,
  da.has_early_agreement,
  da.has_late_agreement,
  ad.discount_reviewed_value > 0 AS has_discount_agreement,
  da.has_owner_approved_review,
  da.has_tenant_approved_review,
  da.has_owner_approved_budget_approval,
  da.has_tenant_approved_budget_approval,
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
  isa.ts_first_owner_access_budget_approval,
  isa.ts_last_owner_access_budget_approval,
  isc.ts_budget_approval_started_by_owner,
  isc.ts_budget_approval_sent_to_tenant,
  isa.ts_first_tenant_access_budget_approval,
  isa.ts_last_tenant_access_budget_approval,
  isc.ts_budget_approval_started_by_tenant,
  isc.ts_reviewed,
  da.ts_owner_approved_review,
  da.ts_tenant_approved_review,
  da.ts_owner_approved_budget_approval,
  da.ts_tenant_approved_budget_approval,
  a.dt_owner_limit_revision AS ts_owner_limit_revision,
  a.dt_tenant_limit_revision AS ts_tenant_limit_revision,
  da.dt_owner_dead_line AS ts_owner_limit_revision_budget_approval,
  da.dt_tenant_dead_line AS ts_tenant_limit_revision_budget_approval,
  ad.dt_bandaid,
  NOW() AS ts_load,
  isa.year,
  isa.month,
  isa.day
FROM
  datalake_amplitude_inspections.inspection_stages_access AS isa
LEFT JOIN
  datalake_inspections.repair_request AS rr
      ON isa.id_inspection = rr.id_inspection
LEFT JOIN
  datalake_inspections.inspection_status_change AS isc
      ON isa.id_inspection = isc.id_inspection
LEFT JOIN
  db_approvals AS da
      ON isa.id_inspection = da.id_inspection
LEFT JOIN 
  assessment AS a
    ON isa.id_inspection = a.id_inspection
LEFT JOIN 
  datalake_inspections.automatic_discounts AS ad
    ON isa.id_client_side = ad.uuid_inspection
GROUP BY
  ALL