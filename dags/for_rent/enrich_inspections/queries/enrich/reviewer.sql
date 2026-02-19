SELECT DISTINCT
  ra.id_reviewer,
  ra.id_user,
  ra.id_assessment,
  a.id_previous_assessment,
  a.id_inspection,
  ra.reviewer_type,
  ra.approval_reason,
  ra.approval_comment,
  ra.approval_type,
  ra.is_approved,
  CASE
    WHEN ra.reviewer_type = "OWNER" THEN a.dt_owner_limit_revision
    WHEN ra.reviewer_type = "TENANT" THEN a.dt_tenant_limit_revision
  END AS dt_limit_revision,
  ra.ts_approved,
  ra.ts_created,
  ra.ts_updated,
  ra.year,
  ra.month,
  ra.day
FROM
  datalake_inspection_services_clean.reviewer AS ra
JOIN
  datalake_inspection_services_clean.assessment AS a
    ON a.id_assessment = ra.id_assessment
