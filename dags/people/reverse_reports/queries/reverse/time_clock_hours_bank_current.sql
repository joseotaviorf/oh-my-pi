-- Current-month hours-bank balances for the time-tracking control dashboard (current tab).
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
    current_month_balances AS (
        SELECT
            hbd.dt_hours_bank_balanced,
            hbd.person_number,
            de.work_email,
            de.name AS employee_name,
            'total' AS segment_label,
            'total' AS group_name,
            (hbd.sum_minutes_running_balance * 60) AS bank_hours,
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
            CASE
                WHEN bu.consolidated_business_unit_name IN ('QuintoAndar SP', 'Classifieds') THEN
                    (hbd.sum_minutes_running_balance * 60.0)
                WHEN bu.consolidated_business_unit_name = 'MLSP'
                    AND (
                        MONTH(hbd.dt_hours_bank_balanced) IN (2, 4, 6, 8, 10, 12)
                        OR (
                            MONTH(hbd.dt_hours_bank_balanced) = MONTH(DATE('{load_start_date}'))
                            AND YEAR(hbd.dt_hours_bank_balanced) = YEAR(DATE('{load_start_date}'))
                        )
                    ) THEN (hbd.sum_minutes_running_balance * 60.0)
                WHEN bu.consolidated_business_unit_name = 'QuintoAndar MG'
                    AND (
                        MONTH(hbd.dt_hours_bank_balanced) IN (6, 12)
                        OR (
                            MONTH(hbd.dt_hours_bank_balanced) = MONTH(DATE('{load_start_date}'))
                            AND YEAR(hbd.dt_hours_bank_balanced) = YEAR(DATE('{load_start_date}'))
                        )
                    ) THEN (hbd.sum_minutes_running_balance * 60.0)
                ELSE 0
            END AS bank_hours_padronizado,
            CASE
                WHEN bu.consolidated_business_unit_name IN ('QuintoAndar SP', 'Classifieds') THEN 1
                WHEN bu.consolidated_business_unit_name = 'MLSP'
                    AND (
                        MONTH(hbd.dt_hours_bank_balanced) IN (2, 4, 6, 8, 10, 12)
                        OR (
                            MONTH(hbd.dt_hours_bank_balanced) = MONTH(DATE('{load_start_date}'))
                            AND YEAR(hbd.dt_hours_bank_balanced) = YEAR(DATE('{load_start_date}'))
                        )
                    ) THEN 1
                WHEN bu.consolidated_business_unit_name = 'QuintoAndar MG'
                    AND (
                        MONTH(hbd.dt_hours_bank_balanced) IN (6, 12)
                        OR (
                            MONTH(hbd.dt_hours_bank_balanced) = MONTH(DATE('{load_start_date}'))
                            AND YEAR(hbd.dt_hours_bank_balanced) = YEAR(DATE('{load_start_date}'))
                        )
                    ) THEN 1
                ELSE 0
            END AS fl_mes_padronizado,
            CONCAT_WS(
                '-',
                '-',
                es.access_list_no_employee,
                (SELECT sa.list_of_super_admins FROM super_admins AS sa),
                '-'
            ) AS access_list_no_employee,
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
            AND MONTH(hbd.dt_hours_bank_balanced) = MONTH(DATE('{load_start_date}'))
            AND YEAR(hbd.dt_hours_bank_balanced) = YEAR(DATE('{load_start_date}'))
    ),
    max_balance_date AS (
        SELECT
            MAX(cmb.dt_hours_bank_balanced) AS max_dt_hours_bank_balanced
        FROM
            current_month_balances AS cmb
    )
SELECT
    cmb.dt_hours_bank_balanced,
    cmb.person_number,
    cmb.work_email,
    cmb.employee_name,
    cmb.segment_label,
    cmb.group_name,
    cmb.bank_hours,
    cmb.centro_de_custo,
    cmb.gestor,
    cmb.l1_email,
    cmb.l2_email,
    cmb.l3_email,
    cmb.l4_email,
    cmb.l5_email,
    cmb.l6_email,
    cmb.l7_email,
    cmb.l8_email,
    cmb.l9_email,
    cmb.empresa,
    cmb.bank_hours_padronizado,
    cmb.fl_mes_padronizado,
    cmb.access_list_no_employee,
    cmb.is_closed,
    CASE
        WHEN cmb.dt_hours_bank_balanced = mbd.max_dt_hours_bank_balanced THEN 1
        ELSE 0
    END AS fl_ultimo_dia_possivel,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    current_month_balances AS cmb
CROSS JOIN
    max_balance_date AS mbd
