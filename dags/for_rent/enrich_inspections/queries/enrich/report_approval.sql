WITH approval_ranked AS (
    SELECT
        r.id_assessment,
        r.id_reviewer,
        r.reviewer_type,
        CAST(r.is_approved AS SMALLINT) AS approved,
        r.dt_limit_revision,
        r.ts_created,
        r.ts_updated,
        ROW_NUMBER() OVER (PARTITION BY r.id_assessment, r.id_reviewer ORDER BY r.ts_updated DESC) AS rn
    FROM
        datalake_inspections.reviewer AS r
    WHERE
        r.mod_is_approved IS TRUE
),
approval AS (
    SELECT
        id_assessment,
        id_reviewer,
        reviewer_type,
        approved,
        dt_limit_revision,
        ts_created,
        ts_updated
    FROM
        approval_ranked
    WHERE
        rn = 1
),
count_approval AS (
    SELECT
        id_assessment,
        SUM(approved) FILTER(WHERE reviewer_type = "OWNER") AS sum_owner_approval,
        SUM(approved) FILTER(WHERE reviewer_type = "TENANT") AS sum_tenant_approval,
        SUM(approved) FILTER(WHERE reviewer_type = "ADMIN") AS sum_admin_approval,
        COUNT(approved) FILTER(WHERE reviewer_type = "OWNER") AS count_owner_approval,
        COUNT(approved) FILTER(WHERE reviewer_type = "TENANT") AS count_tenant_approval,
        COUNT(approved) FILTER(WHERE reviewer_type = "ADMIN") AS count_admin_approval,
        LAST(dt_limit_revision) FILTER(WHERE reviewer_type = "OWNER") AS dt_owner_limit_revision,
        LAST(dt_limit_revision) FILTER(WHERE reviewer_type = "TENANT") AS dt_tenant_limit_revision,
        MIN(ts_updated) AS ts_first_approval,
        MAX(ts_updated) AS ts_last_approval
    FROM
        approval
    GROUP BY 1
)
SELECT
    id_assessment,
    (sum_owner_approval/count_owner_approval) = 1 AS has_owners_approval,
    (sum_tenant_approval/count_tenant_approval) = 1 AS has_tenants_approval,
    (sum_admin_approval/count_admin_approval) = 1 AS has_analysts_approval,
    dt_owner_limit_revision,
    dt_tenant_limit_revision,
    ts_first_approval,
    ts_last_approval,
    NOW() AS ts_load
FROM
    count_approval AS ca
