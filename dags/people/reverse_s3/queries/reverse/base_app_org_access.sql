-- Org Health row-level access matrix for Base44 / S.A.R.A.
-- Migrated from dash_org_health view base_app_org_access (legacy: sandbox base_completa_hierarquia + user_roles).
-- Output grain: one row per (colaborador_id, email_acesso) after natural + matrix UNION and golden-rule filter.
WITH
-- Managers of at least one active employee (legacy: gestores_de_colaboradores_ativos).
active_managers AS (
    SELECT DISTINCT
        LOWER(es.manager_assignment_number) AS manager_assignment_number
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
        AND LOWER(es.status) = 'active'
        AND es.manager_assignment_number IS NOT NULL
),
-- Active employees plus terminated managers still in the tree (legacy roster filter on base_completa_hierarquia).
scoped_employees AS (
    SELECT
        es.assignment_number,
        es.manager_assignment_number,
        es.work_email,
        es.manager_work_email,
        es.band,
        es.access_list,
        es.access_list_no_hrbp,
        es.name_l1,
        es.name_l3
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
        AND (
            LOWER(es.status) = 'active'
            OR EXISTS (
                SELECT
                    1
                FROM
                    active_managers AS am
                WHERE
                    am.manager_assignment_number = LOWER(es.assignment_number)
            )
        )
),
-- Natural-access viewers must be in bands 10–16 (legacy: emails_banda_10_a_16).
band_10_to_16_emails AS (
    SELECT DISTINCT
        LOWER(TRIM(es.work_email)) AS work_email
    FROM
        scoped_employees AS es
    WHERE
        es.work_email IS NOT NULL
        AND TRIM(es.work_email) != ''
        AND TRIM(es.band) IN ('10', '11', '12', '13', '14', '15', '16')
),
-- Stream 1 — explode hierarchy access_list; prefer access_list_no_hrbp when HRBP list is present.
exploded_natural_access AS (
    SELECT
        LOWER(es.assignment_number) AS assignment_number,
        LOWER(TRIM(exploded_email)) AS viewer_email
    FROM
        scoped_employees AS es
    LATERAL VIEW explode(
        split(
            TRIM(
                BOTH '-'
                FROM CASE
                    WHEN es.access_list_no_hrbp = CONCAT('-', '-', '-')
                        OR es.access_list_no_hrbp IS NULL THEN es.access_list
                    ELSE es.access_list_no_hrbp
                END
            ),
            '-'
        )
    ) AS exploded_email
    WHERE
        es.access_list IS NOT NULL
        AND TRIM(BOTH '-' FROM es.access_list) != ''
),
natural_access AS (
    SELECT
        ea.assignment_number,
        ea.viewer_email
    FROM
        exploded_natural_access AS ea
    INNER JOIN
        band_10_to_16_emails AS band_emails
            ON ea.viewer_email = band_emails.work_email
    WHERE
        ea.viewer_email IS NOT NULL
        AND ea.viewer_email != ''
),
-- Stream 2 — matrix roles from org_health_user_roles (legacy: user_roles sheet).
-- super_admin: global access; L1/L3 name match grants that manager scope on the target row.
l1_matrix_access AS (
    SELECT
        LOWER(target.assignment_number) AS assignment_number,
        LOWER(ur.email) AS viewer_email
    FROM
        scoped_employees AS target
    INNER JOIN
        datalake_gsheets_people_clean.org_health_user_roles AS ur
            ON TRIM(LOWER(target.name_l1)) = TRIM(LOWER(ur.special_role))
),
l3_matrix_access AS (
    SELECT
        LOWER(target.assignment_number) AS assignment_number,
        LOWER(ur.email) AS viewer_email
    FROM
        scoped_employees AS target
    INNER JOIN
        datalake_gsheets_people_clean.org_health_user_roles AS ur
            ON TRIM(LOWER(target.name_l3)) = TRIM(LOWER(ur.special_role))
),
super_admin_roles AS (
    SELECT
        LOWER(ur.email) AS viewer_email
    FROM
        datalake_gsheets_people_clean.org_health_user_roles AS ur
    WHERE
        TRIM(LOWER(ur.special_role)) = 'super_admin'
),
super_admin_matrix_access AS (
    SELECT
        LOWER(target.assignment_number) AS assignment_number,
        sar.viewer_email
    FROM
        scoped_employees AS target
    CROSS JOIN
        super_admin_roles AS sar
),
matrix_access AS (
    SELECT
        assignment_number,
        viewer_email
    FROM
        l1_matrix_access
    UNION
    SELECT
        assignment_number,
        viewer_email
    FROM
        l3_matrix_access
    UNION
    SELECT
        assignment_number,
        viewer_email
    FROM
        super_admin_matrix_access
),
combined_access AS (
    SELECT
        assignment_number,
        viewer_email
    FROM
        natural_access
    UNION
    SELECT
        assignment_number,
        viewer_email
    FROM
        matrix_access
)
SELECT
    combined_access.assignment_number AS colaborador_id,
    combined_access.viewer_email AS email_acesso
FROM
    combined_access
LEFT JOIN
    scoped_employees AS target
        ON combined_access.assignment_number = LOWER(target.assignment_number)
LEFT JOIN
    scoped_employees AS viewer
        ON combined_access.viewer_email = LOWER(viewer.work_email)
WHERE
    combined_access.viewer_email IS NOT NULL
    AND combined_access.viewer_email != ''
    AND combined_access.viewer_email != '-'
    -- Golden rule (legacy: regra de ouro) — hardcoded HRBP allow/block lists (aligned with Kevin Trindade).
    AND NOT (
        -- Condition A: viewer reports to a common HRBP lead (legacy: viewer.email_gestor).
        LOWER(COALESCE(viewer.manager_work_email, '')) IN (
            'pedro.bacaltchuk@quintoandar.com.br',
            'larissa.armani@quintoandar.com.br',
            'marilia.marques@quintoandar.com.br',
            'mariana.ayam@quintoandar.com.br'
        )
        AND (
            -- Condition B: target is People leadership, self-view, or direct report of viewer.
            LOWER(COALESCE(target.manager_work_email, '')) IN (
                'deborah.abisaber@quintoandar.com.br',
                'pedro.bacaltchuk@quintoandar.com.br',
                'larissa.armani@quintoandar.com.br',
                'marilia.marques@quintoandar.com.br',
                'mariana.ayam@quintoandar.com.br'
            )
            OR LOWER(target.work_email) = combined_access.viewer_email
            OR LOWER(COALESCE(target.manager_work_email, '')) = combined_access.viewer_email
        )
    )
