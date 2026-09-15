-- Current and terminated employee roster for the X-Ray / Employee Data Center AppSheet.
-- Org overlay (vertical / structure / team) for inclusion CC 906x1x and JA pool
-- 907x1x: match on cost_center_code so accented names (inclusão) still qualify.
-- Spark 3.5 has no recursive CTE, so the manager chain is a fixed 8-hop self-join.
-- Overlay values come from the first manager who is not PwD and not on 906x1x.
-- PwD from dim_employee_disability matches laudo elsewhere: active PIN status only
-- (is_active); pending/inactive rows do not skip a manager as org source.
WITH pwd_people AS (
    SELECT DISTINCT
        dis.person_number
    FROM
        dw_demographics.dim_employee_disability AS dis
    WHERE
        dis.is_active = TRUE
        AND DATE('{load_start_date}') >= dis.dt_valid_from
        AND DATE('{load_start_date}') <= dis.dt_valid_to
),
leadership_org AS (
    SELECT
        LOWER(es.assignment_number) AS assignment_number,
        LOWER(es.manager_assignment_number) AS manager_assignment_number,
        NULLIF(LOWER(es.structure), '-1') AS structure,
        NULLIF(LOWER(es.team), '-1') AS team,
        NULLIF(LOWER(es.vertical), '-1') AS vertical,
        LOWER(es.cost_center_code) = '906x1x' AS is_inclusion_cc,
        (
            COALESCE(es.has_medical_disability_record, FALSE)
            OR COALESCE(es.has_self_declared_pwd, FALSE)
            OR pwd.person_number IS NOT NULL
        ) AS is_pwd
    FROM
        metric_people.employee_snapshots AS es
    LEFT JOIN
        pwd_people AS pwd
            ON es.person_number = pwd.person_number
    WHERE
        es.is_current_for_employee = TRUE
),
manager_chain AS (
    SELECT
        emp.assignment_number,
        CASE
            WHEN m1.assignment_number IS NOT NULL
                AND NOT COALESCE(m1.is_pwd, FALSE)
                AND NOT COALESCE(m1.is_inclusion_cc, FALSE)
            THEN 1
            WHEN m2.assignment_number IS NOT NULL
                AND NOT COALESCE(m2.is_pwd, FALSE)
                AND NOT COALESCE(m2.is_inclusion_cc, FALSE)
            THEN 2
            WHEN m3.assignment_number IS NOT NULL
                AND NOT COALESCE(m3.is_pwd, FALSE)
                AND NOT COALESCE(m3.is_inclusion_cc, FALSE)
            THEN 3
            WHEN m4.assignment_number IS NOT NULL
                AND NOT COALESCE(m4.is_pwd, FALSE)
                AND NOT COALESCE(m4.is_inclusion_cc, FALSE)
            THEN 4
            WHEN m5.assignment_number IS NOT NULL
                AND NOT COALESCE(m5.is_pwd, FALSE)
                AND NOT COALESCE(m5.is_inclusion_cc, FALSE)
            THEN 5
            WHEN m6.assignment_number IS NOT NULL
                AND NOT COALESCE(m6.is_pwd, FALSE)
                AND NOT COALESCE(m6.is_inclusion_cc, FALSE)
            THEN 6
            WHEN m7.assignment_number IS NOT NULL
                AND NOT COALESCE(m7.is_pwd, FALSE)
                AND NOT COALESCE(m7.is_inclusion_cc, FALSE)
            THEN 7
            WHEN m8.assignment_number IS NOT NULL
                AND NOT COALESCE(m8.is_pwd, FALSE)
                AND NOT COALESCE(m8.is_inclusion_cc, FALSE)
            THEN 8
        END AS org_hop,
        m1.vertical AS m1_vertical,
        m1.structure AS m1_structure,
        m1.team AS m1_team,
        m2.vertical AS m2_vertical,
        m2.structure AS m2_structure,
        m2.team AS m2_team,
        m3.vertical AS m3_vertical,
        m3.structure AS m3_structure,
        m3.team AS m3_team,
        m4.vertical AS m4_vertical,
        m4.structure AS m4_structure,
        m4.team AS m4_team,
        m5.vertical AS m5_vertical,
        m5.structure AS m5_structure,
        m5.team AS m5_team,
        m6.vertical AS m6_vertical,
        m6.structure AS m6_structure,
        m6.team AS m6_team,
        m7.vertical AS m7_vertical,
        m7.structure AS m7_structure,
        m7.team AS m7_team,
        m8.vertical AS m8_vertical,
        m8.structure AS m8_structure,
        m8.team AS m8_team
    FROM
        leadership_org AS emp
    LEFT JOIN
        leadership_org AS m1
            ON emp.manager_assignment_number = m1.assignment_number
    LEFT JOIN
        leadership_org AS m2
            ON m1.manager_assignment_number = m2.assignment_number
    LEFT JOIN
        leadership_org AS m3
            ON m2.manager_assignment_number = m3.assignment_number
    LEFT JOIN
        leadership_org AS m4
            ON m3.manager_assignment_number = m4.assignment_number
    LEFT JOIN
        leadership_org AS m5
            ON m4.manager_assignment_number = m5.assignment_number
    LEFT JOIN
        leadership_org AS m6
            ON m5.manager_assignment_number = m6.assignment_number
    LEFT JOIN
        leadership_org AS m7
            ON m6.manager_assignment_number = m7.assignment_number
    LEFT JOIN
        leadership_org AS m8
            ON m7.manager_assignment_number = m8.assignment_number
),
first_non_pwd_leader_org AS (
    SELECT
        mc.assignment_number,
        CASE mc.org_hop
            WHEN 1 THEN mc.m1_vertical
            WHEN 2 THEN mc.m2_vertical
            WHEN 3 THEN mc.m3_vertical
            WHEN 4 THEN mc.m4_vertical
            WHEN 5 THEN mc.m5_vertical
            WHEN 6 THEN mc.m6_vertical
            WHEN 7 THEN mc.m7_vertical
            WHEN 8 THEN mc.m8_vertical
        END AS vertical,
        CASE mc.org_hop
            WHEN 1 THEN mc.m1_structure
            WHEN 2 THEN mc.m2_structure
            WHEN 3 THEN mc.m3_structure
            WHEN 4 THEN mc.m4_structure
            WHEN 5 THEN mc.m5_structure
            WHEN 6 THEN mc.m6_structure
            WHEN 7 THEN mc.m7_structure
            WHEN 8 THEN mc.m8_structure
        END AS structure,
        CASE mc.org_hop
            WHEN 1 THEN mc.m1_team
            WHEN 2 THEN mc.m2_team
            WHEN 3 THEN mc.m3_team
            WHEN 4 THEN mc.m4_team
            WHEN 5 THEN mc.m5_team
            WHEN 6 THEN mc.m6_team
            WHEN 7 THEN mc.m7_team
            WHEN 8 THEN mc.m8_team
        END AS team
    FROM
        manager_chain AS mc
),
tech_team_ranked AS (
    SELECT
        LOWER(tf.assignment_number) AS assignment_number,
        INITCAP(tf.team_1) AS primary_team_tech_exclusive,
        ROW_NUMBER() OVER (
            PARTITION BY LOWER(tf.assignment_number)
            ORDER BY tf.team_1
        ) AS rn
    FROM
        datalake_gsheets_people_clean.team_formation_product_tech AS tf
),
tech_team AS (
    SELECT
        assignment_number,
        primary_team_tech_exclusive
    FROM
        tech_team_ranked
    WHERE
        rn = 1
),
current_hrbp_by_code_ranked AS (
    SELECT
        LOWER(cc.cost_center_code) AS cost_center_code,
        cc.hrbp_work_email,
        ROW_NUMBER() OVER (
            PARTITION BY LOWER(cc.cost_center_code)
            ORDER BY cc.sk_cost_center_version DESC
        ) AS rn
    FROM
        dw_organization.dim_cost_center AS cc
    WHERE
        cc.is_current = TRUE
),
current_hrbp_by_code AS (
    SELECT
        cost_center_code,
        hrbp_work_email
    FROM
        current_hrbp_by_code_ranked
    WHERE
        rn = 1
),
primary_disability_ranked AS (
    SELECT
        dis.person_number,
        dis.disability_status,
        dis.documented_subclassification,
        dis.work_restriction,
        ROW_NUMBER() OVER (
            PARTITION BY dis.person_number
            ORDER BY dis.legislation_code
        ) AS rn
    FROM
        dw_demographics.dim_employee_disability AS dis
    WHERE
        dis.is_primary = TRUE
        AND DATE('{load_start_date}') >= dis.dt_valid_from
        AND DATE('{load_start_date}') <= dis.dt_valid_to
),
primary_disability AS (
    SELECT
        person_number,
        disability_status,
        documented_subclassification,
        work_restriction
    FROM
        primary_disability_ranked
    WHERE
        rn = 1
),
last_compensation_movement_ranked AS (
    SELECT
        fc.person_number,
        fc.dt_valid_from AS dt_ultimo_movimento,
        ed.reason_name_ptb AS tipo_ultimo_movimento,
        fc.pct_adjustment / 100.0 AS pct_ultimo_movimento,
        ROW_NUMBER() OVER (
            PARTITION BY fc.person_number
            ORDER BY fc.dt_valid_from DESC
        ) AS rn
    FROM
        dw_compensation.fact_compensations AS fc
    INNER JOIN
        dw_compensation.dim_event_definition AS ed
            ON fc.sk_event_definition = ed.sk_event_definition
    WHERE
        ed.reason_name_ptb IN ('Mérito', 'Promoção', 'Recrutamento Interno')
        AND fc.dt_valid_from <= DATE('{load_start_date}')
        AND COALESCE(fc.amount_adjustment, 0) > 0
        AND (
            fc.pct_adjustment IS NULL
            OR fc.pct_adjustment >= 1
        )
),
last_compensation_movement AS (
    SELECT
        person_number,
        dt_ultimo_movimento,
        tipo_ultimo_movimento,
        pct_ultimo_movimento
    FROM
        last_compensation_movement_ranked
    WHERE
        rn = 1
),
employee_base AS (
    SELECT
        es.consolidated_business_unit_name AS empresa,
        LOWER(es.assignment_number) AS id_colaborador,
        es.person_number AS matricula,
        INITCAP(es.name) AS nome,
        LOWER(es.work_email) AS email,
        CASE
            WHEN es.status = 'Active' THEN 'Active'
            ELSE 'Dismissed'
        END AS status,
        LOWER(es.band) AS banda,
        INITCAP(
            COALESCE(
                NULLIF(es.manager_name, ''),
                mgr_emp.name
            )
        ) AS gestor,
        INITCAP(es.job_name) AS cargo,
        INITCAP(
            CASE
                WHEN LOWER(TRIM(es.job_family)) IN ('analysts', 'analistas') THEN 'Analysts'
                WHEN LOWER(TRIM(es.job_family)) IN ('assistants', 'assistentes') THEN 'Assistants'
                WHEN LOWER(TRIM(es.job_family)) IN ('auxiliaries', 'auxiliares') THEN 'Auxiliaries'
                WHEN LOWER(TRIM(es.job_family)) = 'c-level' THEN 'C-level'
                WHEN LOWER(TRIM(es.job_family)) IN ('coordinators', 'coordenadores') THEN 'Coordinators'
                WHEN LOWER(TRIM(es.job_family)) IN ('directors', 'diretores') THEN 'Directors'
                WHEN LOWER(TRIM(es.job_family)) IN ('specialists', 'especialistas') THEN 'Specialists'
                WHEN LOWER(TRIM(es.job_family)) IN ('interns', 'intern', 'estagiario', 'estagiarios') THEN 'Interns'
                WHEN LOWER(TRIM(es.job_family)) IN ('managers', 'gerentes') THEN 'Managers'
                WHEN LOWER(TRIM(es.job_family)) IN (
                    'young apprentices',
                    'young apprentice',
                    'jovem aprendiz'
                ) THEN 'Young Apprentices'
                WHEN LOWER(TRIM(es.job_family)) IN ('supervisors', 'supervisores') THEN 'Supervisors'
                WHEN LOWER(TRIM(es.job_family)) IN ('vice-presidents', 'vice-presidentes', 'vice presidentes') THEN 'Vice-presidents'
                WHEN es.job_family IS NULL THEN NULL
                ELSE es.job_family
            END
        ) AS classe_cargo,
        INITCAP(
            CONCAT(
                LOWER(es.cost_center_code),
                ' - ',
                CASE
                    WHEN es.cost_center_name ILIKE CONCAT(es.cost_center_code, ' - %')
                        THEN LOWER(SUBSTRING(es.cost_center_name, LENGTH(es.cost_center_code) + 4))
                    ELSE LOWER(COALESCE(es.cost_center_name, ''))
                END
            )
        ) AS centro_de_custo,
        LOWER(es.cost_center_code) AS cost_center_code,
        (
            (
                LOWER(es.band) LIKE '%ja%'
                AND LOWER(es.cost_center_code) = '907x1x'
            )
            OR LOWER(es.cost_center_code) = '906x1x'
        ) AS needs_org_overlay,
        NULLIF(LOWER(es.vertical), '-1') AS vertical_raw,
        NULLIF(LOWER(es.structure), '-1') AS structure_raw,
        NULLIF(LOWER(es.team), '-1') AS team_raw,
        INITCAP(NULLIF(LOWER(es.business), '-1')) AS business,
        INITCAP(NULLIF(LOWER(es.product), '-1')) AS product,
        tt.primary_team_tech_exclusive AS primary_team_tech_exclusive,
        CASE
            WHEN LOWER(es.status) = 'active'
            THEN es.months_tenure_in_band
            ELSE NULL
        END AS tempo_na_banda_em_meses,
        INITCAP(NULLIF(es.name_l1, '')) AS L1,
        INITCAP(NULLIF(es.name_l2, '')) AS L2,
        INITCAP(NULLIF(es.name_l3, '')) AS L3,
        INITCAP(NULLIF(es.name_l4, '')) AS L4,
        INITCAP(NULLIF(es.name_l5, '')) AS L5,
        INITCAP(NULLIF(es.name_l6, '')) AS L6,
        INITCAP(NULLIF(es.name_l7, '')) AS L7,
        LOWER(
            COALESCE(
                es.hrbp_work_email,
                cc_current.hrbp_work_email,
                hrbp_by_code.hrbp_work_email
            )
        ) AS hrbp,
        es.count_direct_report AS diretos,
        es.count_total_report AS diretos_e_indiretos,
        CASE
            WHEN es.is_manager = TRUE THEN 'Leader'
            ELSE 'IC'
        END AS is_leader,
        es.dt_employee_hired AS dt_inicio,
        es.dt_terminated AS dt_desligamento,
        INITCAP(es.termination_type) AS motivo_desligamento,
        es.registered_sex AS sexo,
        es.dt_birth AS dt_nascimento,
        es.salary_table AS tabela_salarial,
        es.amount_salary AS salario,
        CONCAT_WS(
            ', ',
            INITCAP(es.address_street),
            INITCAP(es.address_number),
            INITCAP(es.address_complement),
            INITCAP(es.address_district)
        ) AS address,
        CONCAT_WS(
            ', ',
            INITCAP(es.address_city),
            INITCAP(es.address_state),
            es.address_zip_code
        ) AS address_city_state_zip,
        es.full_phone_number AS numero_celular,
        CASE
            WHEN es.months_employee_tenure IS NULL THEN NULL
            WHEN es.months_employee_tenure < 3 THEN 'A. Less than 3 months'
            WHEN es.months_employee_tenure <= 5 THEN 'B. 3 to 5 months'
            WHEN es.months_employee_tenure <= 12 THEN 'C. 6 to 12 months'
            WHEN es.months_employee_tenure <= 18 THEN 'D. 13 to 18 months'
            WHEN es.months_employee_tenure <= 24 THEN 'E. 19 to 24 months'
            WHEN es.months_employee_tenure <= 36 THEN 'F. 25 to 36 months'
            ELSE 'G. More than 36 months'
        END AS tenure,
        -- Lake range_position is percent of midpoint (~98). Export the ratio
        -- (0.98) so AppSheet/sheet can apply its own percent scale.
        es.range_position / 100 AS pos_faixa,
        es.salary_range_mid AS referencia,
        CASE
            WHEN es.talent_potential IS NULL OR TRIM(CAST(es.talent_potential AS STRING)) IN ('', '-', '-1')
            THEN NULL
            ELSE es.talent_potential
        END AS potencial,
        CASE
            WHEN es.talent_criticality IS NULL OR TRIM(CAST(es.talent_criticality AS STRING)) IN ('', '-', '-1')
            THEN NULL
            ELSE es.talent_criticality
        END AS criticidade,
        CAST(FROM_UTC_TIMESTAMP(es.ts_load, 'America/Sao_Paulo') AS DATE) AS dt_last_update,
        es.country AS pais,
        NULLIF(
            CASE
                WHEN comp_job.target_plr_salary_multiplier > 0
                THEN CAST(comp_job.target_plr_salary_multiplier AS DOUBLE)
                ELSE CAST(comp_job.target_plr AS DOUBLE)
            END,
            0
        ) AS target_rv,
        CASE CAST(es.perf_impact_score AS INT)
            WHEN 150 THEN 'A. Outstanding'
            WHEN 120 THEN 'B. Above Expectations'
            WHEN 100 THEN 'C. Meets Expectations'
            WHEN 70 THEN 'D. Partially Misses Expectations'
            WHEN 0 THEN 'E. Insufficient'
        END AS impacto,
        CASE CAST(es.perf_behavior_score AS INT)
            WHEN 150 THEN 'A. Outstanding'
            WHEN 120 THEN 'B. Above Expectations'
            WHEN 100 THEN 'C. Meets Expectations'
            WHEN 70 THEN 'D. Partially Misses Expectations'
            WHEN 0 THEN 'E. Insufficient'
        END AS comportamento,
        CASE CAST(es.perf_leadership_score AS INT)
            WHEN 150 THEN 'A. Outstanding'
            WHEN 120 THEN 'B. Above Expectations'
            WHEN 100 THEN 'C. Meets Expectations'
            WHEN 70 THEN 'D. Partially Misses Expectations'
            WHEN 0 THEN 'E. Insufficient'
        END AS lideranca_pr,
        CASE LOWER(TRIM(CAST(es.perf_final_range AS STRING)))
            WHEN 'outstanding' THEN 'A. Outstanding'
            WHEN 'above expectations' THEN 'B. Above Expectations'
            WHEN 'meets expectations' THEN 'C. Meets Expectations'
            WHEN 'partially misses expectations' THEN 'D. Partially Misses Expectations'
            WHEN 'insufficient' THEN 'E. Insufficient'
        END AS faixa_pr,
        CASE
            WHEN es.talent_readiness IS NULL
                OR TRIM(CAST(es.talent_readiness AS STRING)) IN ('', '-', '-1')
            THEN NULL
            ELSE es.talent_readiness
        END AS prontidao,
        CASE
            WHEN es.talent_risk_of_loss IS NULL
                OR TRIM(CAST(es.talent_risk_of_loss AS STRING)) IN ('', '-', '-1')
            THEN NULL
            ELSE es.talent_risk_of_loss
        END AS risco_de_perda,
        -- Legacy X-Ray always injected gbraga as L0 (People Insights ACL for
        -- terminated rows whose hierarchy L0 is empty). Dedup when email_l0 is
        -- already that address.
        ARRAY_JOIN(
            ARRAY_DISTINCT(
                FILTER(
                    ARRAY(
                        'gbraga@quintoandar.com.br',
                        LOWER(es.email_l0),
                        LOWER(es.email_l1),
                        LOWER(es.email_l2),
                        LOWER(es.email_l3),
                        LOWER(es.email_l4),
                        LOWER(es.email_l5),
                        LOWER(es.email_l6),
                        LOWER(es.email_l7),
                        LOWER(
                            COALESCE(
                                es.hrbp_work_email,
                                cc_current.hrbp_work_email,
                                hrbp_by_code.hrbp_work_email
                            )
                        ),
                        LOWER(es.work_email)
                    ),
                    x -> x IS NOT NULL AND x <> ''
                )
            ),
            ','
        ) AS access_list
    FROM
        metric_people.employee_snapshots AS es
    LEFT JOIN
        dw_organization.dim_cost_center AS cc
            ON cc.sk_cost_center_version = es.sk_cost_center_version
    LEFT JOIN
        dw_organization.dim_cost_center AS cc_current
            ON cc_current.id_organization = cc.id_organization
            AND cc_current.is_current = TRUE
    LEFT JOIN
        current_hrbp_by_code AS hrbp_by_code
            ON hrbp_by_code.cost_center_code = LOWER(es.cost_center_code)
    LEFT JOIN
        tech_team AS tt
            ON LOWER(es.assignment_number) = tt.assignment_number
    LEFT JOIN
        dw_employee_details.fact_assignment_snapshots AS mgr_fas
            ON mgr_fas.assignment_number = es.manager_assignment_number
            AND mgr_fas.is_current_for_assignment = TRUE
    LEFT JOIN
        dw_employee_details.dim_employee AS mgr_emp
            ON mgr_emp.sk_employee = mgr_fas.sk_employee
    LEFT JOIN
        dw_compensation.dim_job AS comp_job
            ON comp_job.sk_job_version = es.sk_job_version
    WHERE
        es.is_current_for_employee = TRUE
)
SELECT
    eb.empresa,
    eb.id_colaborador,
    eb.matricula,
    eb.nome,
    eb.email,
    eb.status,
    eb.banda,
    eb.gestor,
    eb.cargo,
    eb.classe_cargo,
    eb.centro_de_custo,
    INITCAP(
        CASE
            WHEN eb.needs_org_overlay = TRUE
            THEN COALESCE(fnpl.vertical, eb.vertical_raw)
            ELSE eb.vertical_raw
        END
    ) AS vertical,
    INITCAP(
        CASE
            WHEN eb.needs_org_overlay = TRUE
            THEN COALESCE(fnpl.structure, eb.structure_raw)
            ELSE eb.structure_raw
        END
    ) AS structure,
    INITCAP(
        CASE
            WHEN eb.needs_org_overlay = TRUE
            THEN COALESCE(fnpl.team, eb.team_raw)
            ELSE eb.team_raw
        END
    ) AS team,
    eb.business,
    eb.product,
    eb.primary_team_tech_exclusive,
    eb.tempo_na_banda_em_meses,
    eb.L1,
    eb.L2,
    eb.L3,
    eb.L4,
    eb.L5,
    eb.L6,
    eb.L7,
    eb.hrbp,
    eb.diretos,
    eb.diretos_e_indiretos,
    eb.is_leader,
    eb.dt_inicio,
    eb.dt_desligamento,
    eb.motivo_desligamento,
    eb.sexo,
    eb.dt_nascimento,
    dis.disability_status,
    dis.documented_subclassification,
    dis.work_restriction,
    eb.tabela_salarial,
    eb.salario,
    lcm.pct_ultimo_movimento,
    lcm.tipo_ultimo_movimento,
    lcm.dt_ultimo_movimento,
    eb.address,
    eb.address_city_state_zip,
    eb.numero_celular,
    eb.tenure,
    eb.pos_faixa,
    eb.referencia,
    eb.potencial,
    eb.criticidade,
    eb.dt_last_update,
    eb.pais,
    eb.target_rv,
    eb.impacto,
    eb.comportamento,
    eb.lideranca_pr,
    eb.faixa_pr,
    eb.prontidao,
    eb.risco_de_perda,
    eb.access_list,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    employee_base AS eb
LEFT JOIN
    primary_disability AS dis
        ON eb.matricula = dis.person_number
LEFT JOIN
    last_compensation_movement AS lcm
        ON eb.matricula = lcm.person_number
LEFT JOIN
    first_non_pwd_leader_org AS fnpl
        ON eb.id_colaborador = fnpl.assignment_number
