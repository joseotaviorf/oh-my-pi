WITH owner_approvals AS (
    SELECT
        *
    FROM
        datalake_inspection_services_clean.reviewer
    WHERE
        reviewer_type = 'OWNER'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_assessment ORDER BY ts_updated DESC) = 1
),
tenant_approvals AS (
    SELECT
        *
    FROM
        datalake_inspection_services_clean.reviewer
    WHERE
        reviewer_type = 'TENANT'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_assessment ORDER BY ts_updated DESC) = 1
),
assessment AS (
    SELECT
        *
    FROM
        datalake_inspection_services_clean.assessment
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_inspection ORDER BY ts_updated DESC) = 1
),
union_reviewer_approvals AS (
    SELECT
        a.id_inspection,
        COALESCE(ra_owner.id_assessment, ra_tenant.id_assessment) AS id_assessment,
        a.id_previous_assessment,
        NULL AS id_budget,
        CASE
          WHEN ra_owner.is_approved = true THEN ra_owner.id_reviewer
        END AS owner_approved_by,
        CASE
          WHEN ra_tenant.is_approved = true THEN ra_tenant.id_reviewer
        END AS tenant_approved_by,
        ra_owner.approval_comment AS owner_approval_comment,
        ra_tenant.approval_comment AS tenant_approval_comment,
        ra_owner.approval_reason AS owner_approval_reason,
        ra_tenant.approval_reason AS tenant_approval_reason,
        COALESCE(ra_owner.approval_type, ra_tenant.approval_type) AS approval_type,
        ra_owner.is_approved AS owner_approved,
        ra_tenant.is_approved AS tenant_approved,
        ra_owner.ts_approved AS ts_owner_approved,
        ra_tenant.ts_approved AS ts_tenant_approved,
        a.dt_owner_limit_revision,
        a.dt_tenant_limit_revision,
        COALESCE(ra_owner.ts_created, ra_tenant.ts_created) AS ts_created,
        COALESCE(ra_owner.ts_updated, ra_tenant.ts_updated) AS ts_updated,
        COALESCE(ra_owner.year, ra_tenant.year) AS year,
        COALESCE(ra_owner.month, ra_tenant.month) AS month,
        COALESCE(ra_owner.day, ra_tenant.day) AS day
    FROM
        owner_approvals AS ra_owner
    FULL OUTER JOIN
        tenant_approvals AS ra_tenant
          ON ra_owner.id_assessment = ra_tenant.id_assessment
    FULL OUTER JOIN
        assessment AS a
          ON a.id_assessment = ra_owner.id_assessment
          OR a.id_assessment = ra_tenant.id_assessment
    WHERE
        DATE(COALESCE(ra_owner.ts_updated, ra_tenant.ts_updated)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY a.id_inspection ORDER BY COALESCE(ra_owner.ts_updated, ra_tenant.ts_updated) DESC) = 1
    UNION ALL
    SELECT
        b.id_inspection,
        a.id_assessment,
        a.id_previous_assessment,
        b.id_budget,
        b.owner_approved_by,
        b.tenant_approved_by,
        b.owner_approval_comment,
        b.tenant_approval_comment,
        b.owner_approval_reason,
        b.tenant_approval_reason,
        'BUDGET_APPROVAL' AS approval_type,
        b.owner_approved,
        b.tenant_approved,
        b.dt_owner_approved AS ts_owner_approved,
        b.dt_tenant_approved AS ts_tenant_approved,
        b.dt_owner_dead_line AS dt_owner_limit_revision,
        b.dt_tenant_dead_line AS dt_tenant_limit_revision,
        b.ts_created,
        b.ts_updated,
        b.year,
        b.month,
        b.day
    FROM
        datalake_inspection_services_clean.budget AS b
    LEFT JOIN
        assessment AS a
            ON a.id_inspection = b.id_inspection
    WHERE
        MAKE_DATE(b.year, b.month, b.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY b.id_inspection ORDER BY b.ts_updated DESC) = 1
)
SELECT
    ura.id_inspection,
    ura.id_assessment,
    ura.id_previous_assessment,
    ura.id_budget,
    b.total_cost,
    b.owner_amount_payment,
    b.tenant_amount_payment,
    ura.owner_approved_by,
    ura.tenant_approved_by,
    ura.owner_approval_comment,
    ura.tenant_approval_comment,
    ura.owner_approval_reason,
    ura.tenant_approval_reason,
    ura.approval_type,
    ura.owner_approved,
    ura.tenant_approved,
    ura.ts_owner_approved,
    ura.ts_tenant_approved,
    ura.dt_owner_limit_revision,
    ura.dt_tenant_limit_revision,
    ura.ts_created,
    ura.ts_updated,
    ura.year,
    ura.month,
    ura.day
FROM
    union_reviewer_approvals AS ura
LEFT JOIN
    datalake_inspection_services_clean.budget AS b
      ON b.id_inspection = ura.id_inspection
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ura.id_inspection ORDER BY ura.ts_updated DESC) = 1
