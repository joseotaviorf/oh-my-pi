WITH owner_approvals_ranked AS (
    SELECT
        r.*,
        ROW_NUMBER() OVER (PARTITION BY r.id_assessment ORDER BY r.ts_updated DESC) AS rn
    FROM
        datalake_inspection_services_clean.reviewer AS r
    WHERE
        r.reviewer_type = 'OWNER'
),
owner_approvals AS (
    SELECT
        *
    FROM
        owner_approvals_ranked
    WHERE
        rn = 1
),
tenant_approvals_ranked AS (
    SELECT
        r.*,
        ROW_NUMBER() OVER (PARTITION BY r.id_assessment ORDER BY r.ts_updated DESC) AS rn
    FROM
        datalake_inspection_services_clean.reviewer AS r
    WHERE
        r.reviewer_type = 'TENANT'
),
tenant_approvals AS (
    SELECT
        *
    FROM
        tenant_approvals_ranked
    WHERE
        rn = 1
),
assessment_ranked AS (
    SELECT
        a.*,
        ROW_NUMBER() OVER (PARTITION BY a.id_inspection ORDER BY a.ts_updated DESC) AS rn
    FROM
        datalake_inspection_services_clean.assessment AS a
),
assessment AS (
    SELECT
        *
    FROM
        assessment_ranked
    WHERE
        rn = 1
),
reviewer_approvals_base AS (
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
        NULL AS is_early_both_agree,
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
          -- The join above already equates both id_assessment columns, so the reviewer
          -- side always exposes a single key: whichever of the two is present.
          ON a.id_assessment = COALESCE(ra_owner.id_assessment, ra_tenant.id_assessment)
    WHERE
        DATE(COALESCE(ra_owner.ts_updated, ra_tenant.ts_updated)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
reviewer_approvals AS (
    SELECT
        *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY id_inspection
                ORDER BY ts_updated DESC
            ) AS rn
        FROM
            reviewer_approvals_base
    )
    WHERE
        rn = 1
),
budget_approvals_base AS (
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
        b.is_early_both_agree,
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
),
budget_approvals AS (
    SELECT
        *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY id_inspection ORDER BY ts_updated DESC) AS rn
        FROM
            budget_approvals_base
    )
    WHERE
        rn = 1
),
union_reviewer_approvals AS (
    SELECT
        id_inspection,
        id_assessment,
        id_previous_assessment,
        id_budget,
        owner_approved_by,
        tenant_approved_by,
        owner_approval_comment,
        tenant_approval_comment,
        owner_approval_reason,
        tenant_approval_reason,
        approval_type,
        owner_approved,
        tenant_approved,
        is_early_both_agree,
        ts_owner_approved,
        ts_tenant_approved,
        dt_owner_limit_revision,
        dt_tenant_limit_revision,
        ts_created,
        ts_updated,
        year,
        month,
        day
    FROM
        reviewer_approvals
    UNION ALL
    SELECT
        id_inspection,
        id_assessment,
        id_previous_assessment,
        id_budget,
        owner_approved_by,
        tenant_approved_by,
        owner_approval_comment,
        tenant_approval_comment,
        owner_approval_reason,
        tenant_approval_reason,
        approval_type,
        owner_approved,
        tenant_approved,
        is_early_both_agree,
        ts_owner_approved,
        ts_tenant_approved,
        dt_owner_limit_revision,
        dt_tenant_limit_revision,
        ts_created,
        ts_updated,
        year,
        month,
        day
    FROM
        budget_approvals
),
report_approvals_ranked AS (
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
        ura.is_early_both_agree,
        ura.ts_owner_approved,
        ura.ts_tenant_approved,
        ura.dt_owner_limit_revision,
        ura.dt_tenant_limit_revision,
        ura.ts_created,
        ura.ts_updated,
        ura.year,
        ura.month,
        ura.day,
        ROW_NUMBER() OVER (PARTITION BY ura.id_inspection ORDER BY ura.ts_updated DESC) AS rn
    FROM
        union_reviewer_approvals AS ura
    LEFT JOIN
        datalake_inspection_services_clean.budget AS b
          ON b.id_inspection = ura.id_inspection
)
SELECT
    id_inspection,
    id_assessment,
    id_previous_assessment,
    id_budget,
    total_cost,
    owner_amount_payment,
    tenant_amount_payment,
    owner_approved_by,
    tenant_approved_by,
    owner_approval_comment,
    tenant_approval_comment,
    owner_approval_reason,
    tenant_approval_reason,
    approval_type,
    owner_approved,
    tenant_approved,
    is_early_both_agree,
    ts_owner_approved,
    ts_tenant_approved,
    dt_owner_limit_revision,
    dt_tenant_limit_revision,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    report_approvals_ranked
WHERE
    rn = 1
