WITH
    current_snapshots AS (
        SELECT
            snap.sk_cost_center_version,
            snap.is_active
        FROM
            dw_employee_details.fact_assignment_snapshots AS snap
        WHERE
            snap.is_current_for_assignment = TRUE
            AND COALESCE(snap.is_transfer_termination, FALSE) = FALSE
    ),
    total_headcount AS (
        SELECT
            sk_cost_center_version,
            COUNT(1) AS total_hc
        FROM
            current_snapshots
        GROUP BY
            sk_cost_center_version
    ),
    active_headcount AS (
        SELECT
            sk_cost_center_version,
            COUNT(1) AS active_hc
        FROM
            current_snapshots
        WHERE
            is_active = TRUE
        GROUP BY
            sk_cost_center_version
    ),
    inactive_headcount AS (
        SELECT
            sk_cost_center_version,
            COUNT(1) AS inactive_hc
        FROM
            current_snapshots
        WHERE
            is_active = FALSE
        GROUP BY
            sk_cost_center_version
    ),
    cost_center_base AS (
        SELECT
            cc.cost_center_name AS centro_de_custo,
            cc.cost_center_code AS cc_code,
            CASE
                WHEN cc.is_active THEN 'ativo'
                ELSE 'inativo'
            END AS status,
            NULLIF(cc.vertical, '-1') AS vertical,
            NULLIF(cc.owner_l1_name, '-1') AS l1_cc,
            NULLIF(cc.owner_l2_name, '-1') AS l2_cc,
            LOWER(cc.hrbp_work_email) AS hrbp,
            COALESCE(ahc.active_hc, 0) AS active_hc,
            COALESCE(ihc.inactive_hc, 0) AS inactive_hc,
            COALESCE(thc.total_hc, 0) AS total_hc,
            cc.ts_created,
            ROW_NUMBER() OVER (
                PARTITION BY
                    cc.cost_center_code
                ORDER BY
                    CASE
                        WHEN cc.is_active THEN 'ativo'
                        ELSE 'inativo'
                    END,
                    cc.ts_created DESC
            ) AS rn
        FROM
            dw_organization.dim_cost_center AS cc
        LEFT JOIN
            total_headcount AS thc
                ON thc.sk_cost_center_version = cc.sk_cost_center_version
        LEFT JOIN
            active_headcount AS ahc
                ON ahc.sk_cost_center_version = cc.sk_cost_center_version
        LEFT JOIN
            inactive_headcount AS ihc
                ON ihc.sk_cost_center_version = cc.sk_cost_center_version
        WHERE
            cc.cost_center_code IS NOT NULL
            AND cc.is_current = TRUE
    )
SELECT
    centro_de_custo,
    cc_code,
    status,
    vertical,
    l1_cc,
    l2_cc,
    hrbp,
    active_hc,
    inactive_hc,
    total_hc,
    ts_created,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    cost_center_base
WHERE
    rn = 1
ORDER BY
    ts_created,
    cc_code
