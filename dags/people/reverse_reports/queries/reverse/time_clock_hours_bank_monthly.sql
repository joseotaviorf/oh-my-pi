-- Monthly hours-bank balances for the time-tracking control dashboard (horas_extras tab).
-- Uses dw_time.fact_hours_bank_daily_totals (OiTchau UI Banco Acumulado parity).
WITH
    exempt_managers AS (
        SELECT DISTINCT
            hbt.person_number
        FROM
            dw_time.fact_hours_bank_rule_totals AS hbt
        LEFT JOIN
            dw_time.dim_hours_bank_rule AS hbr
                ON hbr.sk_hours_bank_rule = hbt.sk_hours_bank_rule
        WHERE
            hbr.group_name = 'Gestores_Isentos'
    ),
    super_admins AS (
        SELECT
            CONCAT_WS(
                '-',
                'frank.storti@quintoandar.com',
                'joao.lyra@quintoandar.com.br',
                'joao.starling@quintoandar.com',
                'mariana.reberte@quintoandar.com.br',
                'michelle.cilento@quintoandar.com.br',
                'kevin.trindade@quintoandar.com.br',
                'julia.mesquita@quintoandar.com.br'
            ) AS list_of_super_admins
    ),
    hours_bank_base AS (
        SELECT
            hbd.dt_hours_bank_balanced,
            hbd.person_number,
            de.work_email,
            de.name AS employee_name,
            'total' AS segment_label,
            'total' AS group_name,
            (hbd.sum_minutes_running_balance * 60) AS bank_hours_original,
            CONCAT(
                LOWER(es.cost_center_code),
                ' - ',
                SUBSTRING(LOWER(es.cost_center_name), 10)
            ) AS centro_de_custo,
            LOWER(es.manager_name) AS gestor,
            LOWER(es.email_l1) AS l1_email,
            LOWER(es.email_l2) AS l2_email,
            LOWER(es.email_l3) AS l3_email,
            LOWER(es.email_l4) AS l4_email,
            LOWER(es.email_l5) AS l5_email,
            LOWER(es.email_l6) AS l6_email,
            LOWER(es.email_l7) AS l7_email,
            LOWER(es.email_l8) AS l8_email,
            LOWER(es.email_l9) AS l9_email,
            bu.consolidated_business_unit_name AS empresa,
            es.access_list_no_employee,
            hbd.is_closed
        FROM
            dw_time.fact_hours_bank_daily_totals AS hbd
        LEFT JOIN
            dw_employee_details.dim_employee AS de
                ON hbd.sk_employee = de.sk_employee
        LEFT JOIN
            exempt_managers AS em
                ON hbd.person_number = em.person_number
        LEFT JOIN
            metric_people.employee_snapshots AS es
                ON LOWER(de.person_number) = LOWER(es.person_number)
                AND es.is_current_for_employee = TRUE
        LEFT JOIN
            dw_organization.dim_business_unit AS bu
                ON bu.sk_business_unit = es.sk_business_unit
        WHERE
            em.person_number IS NULL
            AND (
                es.dt_terminated IS NULL
                OR es.dt_terminated >= DATE('2026-12-31')
            )
    ),
    hours_bank_enriched AS (
        SELECT
            hbb.dt_hours_bank_balanced,
            hbb.person_number,
            hbb.work_email,
            hbb.employee_name,
            hbb.segment_label,
            hbb.group_name,
            hbb.bank_hours_original AS bank_hours,
            hbb.centro_de_custo,
            hbb.gestor,
            hbb.l1_email,
            hbb.l2_email,
            hbb.l3_email,
            hbb.l4_email,
            hbb.l5_email,
            hbb.l6_email,
            hbb.l7_email,
            hbb.l8_email,
            hbb.l9_email,
            hbb.empresa,
            hbb.access_list_no_employee,
            hbb.is_closed,
            hbb.bank_hours_original,
            CASE
                WHEN hbb.empresa IN ('QuintoAndar SP', 'Classifieds') THEN hbb.bank_hours_original
                WHEN hbb.empresa = 'MLSP'
                    AND (
                        MONTH(hbb.dt_hours_bank_balanced) IN (2, 4, 6, 8, 10, 12)
                        OR (
                            MONTH(hbb.dt_hours_bank_balanced) = MONTH(DATE('{load_start_date}'))
                            AND YEAR(hbb.dt_hours_bank_balanced) = YEAR(DATE('{load_start_date}'))
                        )
                    ) THEN hbb.bank_hours_original
                WHEN hbb.empresa = 'QuintoAndar MG'
                    AND (
                        MONTH(hbb.dt_hours_bank_balanced) IN (6, 12)
                        OR (
                            MONTH(hbb.dt_hours_bank_balanced) = MONTH(DATE('{load_start_date}'))
                            AND YEAR(hbb.dt_hours_bank_balanced) = YEAR(DATE('{load_start_date}'))
                        )
                    ) THEN hbb.bank_hours_original
                ELSE 0
            END AS bank_hours_padronizado,
            CASE
                WHEN hbb.empresa IN ('QuintoAndar SP', 'Classifieds') THEN 1
                WHEN hbb.empresa = 'MLSP'
                    AND (
                        MONTH(hbb.dt_hours_bank_balanced) IN (2, 4, 6, 8, 10, 12)
                        OR (
                            MONTH(hbb.dt_hours_bank_balanced) = MONTH(DATE('{load_start_date}'))
                            AND YEAR(hbb.dt_hours_bank_balanced) = YEAR(DATE('{load_start_date}'))
                        )
                    ) THEN 1
                WHEN hbb.empresa = 'QuintoAndar MG'
                    AND (
                        MONTH(hbb.dt_hours_bank_balanced) IN (6, 12)
                        OR (
                            MONTH(hbb.dt_hours_bank_balanced) = MONTH(DATE('{load_start_date}'))
                            AND YEAR(hbb.dt_hours_bank_balanced) = YEAR(DATE('{load_start_date}'))
                        )
                    ) THEN 1
                ELSE 0
            END AS fl_mes_padronizado,
            CONCAT_WS(
                '-',
                '-',
                hbb.access_list_no_employee,
                (SELECT sa.list_of_super_admins FROM super_admins AS sa),
                '-'
            ) AS access_list_no_employee_combined,
            ROW_NUMBER() OVER (
                PARTITION BY
                    hbb.person_number,
                    DATE_TRUNC('month', hbb.dt_hours_bank_balanced)
                ORDER BY
                    hbb.is_closed DESC,
                    hbb.dt_hours_bank_balanced DESC,
                    CASE
                        WHEN hbb.bank_hours_original <> 0 THEN 0
                        ELSE 1
                    END,
                    hbb.bank_hours_original DESC
            ) AS rn
        FROM
            hours_bank_base AS hbb
    )
SELECT
    hbe.dt_hours_bank_balanced,
    hbe.person_number,
    hbe.work_email,
    hbe.employee_name,
    hbe.segment_label,
    hbe.group_name,
    hbe.bank_hours,
    hbe.centro_de_custo,
    hbe.gestor,
    hbe.l1_email,
    hbe.l2_email,
    hbe.l3_email,
    hbe.l4_email,
    hbe.l5_email,
    hbe.l6_email,
    hbe.l7_email,
    hbe.l8_email,
    hbe.l9_email,
    hbe.empresa,
    hbe.bank_hours_padronizado,
    hbe.fl_mes_padronizado,
    hbe.access_list_no_employee_combined AS access_list_no_employee,
    hbe.is_closed,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    hours_bank_enriched AS hbe
WHERE
    hbe.rn = 1
