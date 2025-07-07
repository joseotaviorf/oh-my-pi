WITH repair_exempted AS (
    SELECT
        re.id_repair_request,
        re.id_granted_by,
        re.is_exempted
    FROM
        datalake_inspections.repair_exempted AS re
    QUALIFY
        re.ts_granted = MAX(re.ts_granted) OVER(PARTITION BY re.id_repair_request)
)
SELECT
    r.id_assessment AS sk_assessment,
    r.id_previous_assessment AS sk_previous_assessment,
    CAST(r.id_inspection AS STRING) AS sk_inspection,
    COUNT(DISTINCT rr.id_repair_request) AS total_repair_request,
    COUNT(DISTINCT rr.id_repair_request) FILTER(WHERE r.reviewer_type = 'ADMIN') AS total_repair_request_by_analyst,
    COUNT(DISTINCT rr.id_repair_request) FILTER(WHERE r.reviewer_type = 'OWNER') AS total_repair_request_by_owner,
    COUNT(DISTINCT c.id_repair_request) AS total_repair_contested,
    COUNT(DISTINCT re.id_repair_request) FILTER(WHERE re.is_exempted IS TRUE) AS total_repair_exempted,
    COALESCE(ra.has_owners_approval, FALSE) AS has_owners_approval,
    COALESCE(ra.has_tenants_approval, FALSE) AS has_tenants_approval,
    COALESCE(ra.has_analysts_approval, FALSE) AS has_analysts_approval,
    ira.has_owner_access_review,
    ira.has_tenant_access_review,
    ra.dt_owner_limit_revision,
    ra.dt_tenant_limit_revision,
    is_status.ts_sent_to_repair_analysis,
    is_status.ts_sent_to_owner_review,
    is_status.ts_review_started_by_owner,
    is_status.ts_sent_to_tenant_review,
    is_status.ts_review_started_by_tenant,
    is_status.ts_sent_to_contestation_analysis,
    is_status.ts_reviewed,
    ira.ts_first_owner_access_review,
    ira.ts_last_owner_access_review,
    ira.ts_first_tenant_access_review,
    ira.ts_last_tenant_access_review,
    ra.ts_first_approval,
    ra.ts_last_approval,
    NOW() AS ts_load,
    r.year,
    r.month,
    r.day
FROM
    datalake_inspections.reviewer AS r
LEFT JOIN
    datalake_inspection_services_clean.repair_request AS rr
        ON rr.id_reviewer = r.id_reviewer
LEFT JOIN
    datalake_inspection_services_clean.contestation AS c
        ON c.id_reviewer = r.id_reviewer
LEFT JOIN
    repair_exempted AS re
        ON re.id_granted_by = r.id_reviewer
LEFT JOIN
    datalake_inspections.report_approval AS ra
        ON ra.id_assessment = r.id_assessment
LEFT JOIN
    datalake_amplitude_inspections.inspection_stages_access AS ira
        ON ira.id_inspection = r.id_inspection
LEFT JOIN
    datalake_inspections.inspection_status_change AS is_status
        ON is_status.id_inspection = r.id_inspection
GROUP BY
    1, 2, 3, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32
