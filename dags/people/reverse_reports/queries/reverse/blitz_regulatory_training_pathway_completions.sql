-- Completed Degreed pathways for the Blitz certificate workbook.
-- Exception: Degreed learning enrich/clean tables — no DW equivalent for pathway completion grain (DBP-1454).

WITH
    employee_ranked AS (
        SELECT
            es.person_number,
            es.name,
            LOWER(es.country) AS pais,
            LOWER(es.work_email) AS email,
            bu.consolidated_business_unit_name AS empresa,
            ROW_NUMBER() OVER (
                PARTITION BY
                    es.person_number
                ORDER BY
                    CASE
                        WHEN LOWER(es.status) = 'active' THEN 0
                        ELSE 1
                    END,
                    es.assignment_number DESC
            ) AS rn
        FROM
            metric_people.employee_snapshots AS es
        LEFT JOIN
            dw_organization.dim_business_unit AS bu
                ON bu.sk_business_unit = es.sk_business_unit
        WHERE
            es.is_current = TRUE
            AND es.is_primary_assignment_for_snapshot = TRUE
    ),
    employee_base AS (
        SELECT
            u.id_user,
            COALESCE(e.person_number, u.person_number) AS person_number,
            e.empresa,
            e.name AS nome,
            e.pais,
            e.email
        FROM
            datalake_learning.user_identifier_mapping AS u
        LEFT JOIN
            employee_ranked AS e
                ON u.person_number = e.person_number
                AND e.rn = 1
    ),
    pathway_completions AS (
        SELECT
            id_user,
            id_pathway,
            pct_completed_required,
            dt_completion
        FROM
            datalake_learning.all_completions
        WHERE
            learning_object_type = 'Pathway'
    ),
    pathways AS (
        SELECT
            id AS pathway_id,
            title AS pathway_title
        FROM
            datalake_degreed_clean.pathway_details
    )
SELECT
    c.id_user,
    c.person_number,
    c.empresa,
    c.nome,
    c.pais,
    c.email,
    pc.id_pathway,
    p.pathway_title,
    pc.pct_completed_required,
    pc.dt_completion,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    employee_base AS c
LEFT JOIN
    pathway_completions AS pc
        ON pc.id_user = c.id_user
LEFT JOIN
    pathways AS p
        ON p.pathway_id = pc.id_pathway
WHERE
    pc.pct_completed_required = 100
    AND pc.dt_completion IS NOT NULL
    AND pc.id_pathway IN (
        'Wgdnx', 'zqKvY', 'nwO8w', 'Ypa1l', 'aaWvj', 'ePOE5', 'ljb2N', 'nwg56',
        'Pq05p', 'ePO8X', 'EE5k4', 'yWBpk', 'Xry9A', 'jAvqw', '9Pd4e', '19j4Q',
        'gd2QE', 'YWp8A', 'RjRPk', '9PKel', 'neeKX', 'dZZX0', 'KXWAn', 'jRRBA',
        'V22aj', '5EE8o', 'rvv9g', 'Lllgy', 'NL2qe', 'mqK3a', 'rykPB', 'dZk7O',
        'BjQzP', 'd04VL', '8Bz9W', 'P8Kq3', '41eZL', 'pRwny', 'ERKRx', '75NmQ',
        'dPwv0', 'bBw2o', 'RjgQ5', 'pRNgy', 'k4PR7', 'QQRXj', 'L6Wb7', 'y08qk'
    )
    AND pc.dt_completion >= DATE('2026-04-16')
