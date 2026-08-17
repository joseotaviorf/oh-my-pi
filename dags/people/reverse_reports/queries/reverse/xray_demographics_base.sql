-- TODO(DBP-1447): datalake_people_analytics_sandbox.people_dashboards_super_admins is a
-- manually curated, static ACL list (originally 9 emails, single ts_load, no refresh
-- pipeline; paula.fjesus@quintoandar.com removed per business request) with
-- no equivalent in any of the five governed layers (raw/clean/enrich/dw/metric/qube).
-- Using the sandbox table here would violate the layer-architecture rule, so this list is
-- temporarily hardcoded below to remove the sandbox dependency. Follow-up: migrate this
-- list to a proper datalake_gsheets_people_clean (or similar) table and replace this
-- literal VALUES list with a join against it.
-- Monthly DEI demographics aggregates for X-Ray / Employee Data Center AppSheet.
WITH l1_index AS (
    SELECT
        es.dt_month_reference AS fechamento,
        LOWER(es.email_l1) AS l1_e,
        COUNT(*) AS index_count
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_primary_assignment_for_snapshot = TRUE
    GROUP BY
        es.dt_month_reference,
        LOWER(es.email_l1)
),
super_admins AS (
    SELECT email FROM (
        VALUES
            ('alan.barmak@quintoandar.com.br'),
            ('pedro.prates@quintoandar.com.br'),
            ('kevin.trindade@quintoandar.com.br'),
            ('isabella.araujo@quintoandar.com.br'),
            ('gabriel.berger@quintoandar.com.br'),
            ('leonardo.oliveira@quintoandar.com.br'),
            ('rodrigo.bmartins@quintoandar.com.br'),
            ('julia.mesquita@quintoandar.com.br')
    ) AS t(email)
),
roles_concatenados AS (
    SELECT
        CONCAT(
            '-',
            ARRAY_JOIN(COLLECT_LIST(LOWER(sa.email)), '-'),
            '-'
        ) AS access_list_roles
    FROM
        super_admins AS sa
),
leader_band AS (
    SELECT
        LOWER(es.work_email) AS email,
        TRY_CAST(es.band AS DOUBLE) AS band
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
),
base_inicial AS (
    SELECT
        es.dt_month_reference AS fechamento,
        LOWER(es.country) AS pais,
        NULLIF(LOWER(es.vertical), '-1') AS vertical,
        NULLIF(LOWER(es.structure), '-1') AS structure,
        NULLIF(LOWER(es.team), '-1') AS team,
        CASE
            WHEN es.consolidated_business_unit_name IN ('Benvi México', 'Benvi Mexico') THEN 'Benvi Mexico'
            WHEN es.consolidated_business_unit_name = 'ATTA' THEN 'Atta'
            WHEN es.consolidated_business_unit_name IS NULL THEN 'N/A'
            ELSE es.consolidated_business_unit_name
        END AS empresa,
        CASE
            WHEN es.has_medical_disability_record = TRUE
                OR es.has_self_declared_pwd = TRUE THEN 'b. PwD'
            ELSE 'a. Non-PwD'
        END AS pwd,
        CASE
            WHEN es.is_underrepresented_race = FALSE THEN 'a. Non-BIM'
            WHEN es.is_underrepresented_race = TRUE THEN 'b. BIM'
            ELSE 'c. Not answered'
        END AS bim,
        CASE
            WHEN es.is_woman = TRUE THEN 'b. Women'
            WHEN es.is_woman = FALSE THEN 'a. Non-women'
            ELSE 'd. Not answered'
        END AS women,
        CASE
            WHEN es.is_lgbtqia = TRUE THEN 'b. LGBT+'
            WHEN es.is_lgbtqia = FALSE THEN 'a. Non-LGBT+'
            ELSE 'c. Not answered'
        END AS lgbt,
        CASE
            WHEN es.is_lgbtqia = TRUE
                OR es.is_woman = TRUE
                OR es.is_underrepresented_race = TRUE
                OR es.has_medical_disability_record = TRUE
                OR es.has_self_declared_pwd = TRUE THEN 'b. URG'
            WHEN es.is_lgbtqia IS NULL
                OR es.is_woman IS NULL
                OR es.is_underrepresented_race IS NULL THEN 'c. Not answered'
            ELSE 'a. Non-URG'
        END AS urg,
        CASE
            WHEN es.age_in_years IS NULL THEN NULL
            WHEN es.age_in_years < 21 THEN 'a. Under 21 years'
            WHEN es.age_in_years <= 25 THEN 'b. 21 to 25 years'
            WHEN es.age_in_years <= 30 THEN 'c. 26 to 30 years'
            WHEN es.age_in_years <= 35 THEN 'd. 31 to 35 years'
            WHEN es.age_in_years <= 40 THEN 'e. 36 to 40 years'
            WHEN es.age_in_years <= 45 THEN 'f. 41 to 45 years'
            WHEN es.age_in_years <= 50 THEN 'g. 46 to 50 years'
            WHEN es.age_in_years <= 55 THEN 'h. 51 to 55 years'
            ELSE 'i. Over 55 years'
        END AS faixa_etaria,
        CASE
            WHEN es.months_employee_tenure IS NULL
                AND es.dt_employee_hired IS NULL THEN NULL
            WHEN COALESCE(
                es.months_employee_tenure,
                CAST(MONTHS_BETWEEN(es.dt_month_reference, es.dt_employee_hired) AS INT)
            ) < 3 THEN 'a. Less than 3 months'
            WHEN COALESCE(
                es.months_employee_tenure,
                CAST(MONTHS_BETWEEN(es.dt_month_reference, es.dt_employee_hired) AS INT)
            ) <= 5 THEN 'b. 3 to 5 months'
            WHEN COALESCE(
                es.months_employee_tenure,
                CAST(MONTHS_BETWEEN(es.dt_month_reference, es.dt_employee_hired) AS INT)
            ) <= 12 THEN 'c. 6 to 12 months'
            WHEN COALESCE(
                es.months_employee_tenure,
                CAST(MONTHS_BETWEEN(es.dt_month_reference, es.dt_employee_hired) AS INT)
            ) <= 18 THEN 'd. 13 to 18 months'
            WHEN COALESCE(
                es.months_employee_tenure,
                CAST(MONTHS_BETWEEN(es.dt_month_reference, es.dt_employee_hired) AS INT)
            ) <= 24 THEN 'e. 19 to 24 months'
            WHEN COALESCE(
                es.months_employee_tenure,
                CAST(MONTHS_BETWEEN(es.dt_month_reference, es.dt_employee_hired) AS INT)
            ) <= 36 THEN 'f. 25 to 36 months'
            WHEN COALESCE(
                es.months_employee_tenure,
                CAST(MONTHS_BETWEEN(es.dt_month_reference, es.dt_employee_hired) AS INT)
            ) <= 48 THEN 'g. 37 to 48 months'
            WHEN COALESCE(
                es.months_employee_tenure,
                CAST(MONTHS_BETWEEN(es.dt_month_reference, es.dt_employee_hired) AS INT)
            ) <= 60 THEN 'h. 49 to 60 months'
            ELSE 'i. Over 60 months'
        END AS tenure,
        es.count_direct_report AS diretos,
        CASE
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) IN ('analistas', 'analysts') THEN 'Analysts'
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) IN ('assistentes', 'assistants') THEN 'Assistants'
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) IN ('auxiliares', 'auxiliaries') THEN 'Auxiliaries'
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) = 'c-level' THEN 'C-level'
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) IN ('coordenadores', 'coordinators') THEN 'Coordinators'
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) IN ('diretores', 'directors') THEN 'Directors'
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) IN ('especialistas', 'specialists') THEN 'Specialists'
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) IN ('estagiarios', 'estagiario', 'interns') THEN 'Interns'
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) IN ('gerentes', 'managers') THEN 'Managers'
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) IN ('jovem aprendiz', 'young apprentices') THEN 'Young apprentices'
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) IN ('supervisores', 'supervisors') THEN 'Supervisors'
            WHEN LOWER(TRIM(COALESCE(es.job_family, ''))) IN (
                'vice-presidentes',
                'vice presidentes',
                'vice-presidents'
            ) THEN 'Vice-presidents'
            WHEN es.job_family IS NULL OR TRIM(es.job_family) IN ('', '-') THEN NULL
            ELSE INITCAP(es.job_family)
        END AS classe_cargo,
        CASE
            WHEN es.is_manager = TRUE THEN 'b. Leader'
            ELSE 'a. Non-leader'
        END AS fl_lider,
        CASE
            WHEN LOWER(TRIM(COALESCE(CAST(es.talent_potential AS STRING), ''))) IN ('', '-', '-1') THEN NULL
            WHEN LOWER(CAST(es.talent_potential AS STRING)) IN ('alto', 'high') THEN 'a. High'
            WHEN LOWER(CAST(es.talent_potential AS STRING)) IN ('medio', 'medium') THEN 'b. Medium'
            WHEN LOWER(CAST(es.talent_potential AS STRING)) IN ('baixo', 'low') THEN 'c. Low'
            ELSE NULL
        END AS potencial,
        CASE
            WHEN LOWER(TRIM(COALESCE(CAST(es.talent_criticality AS STRING), ''))) IN ('', '-', '-1') THEN NULL
            WHEN LOWER(CAST(es.talent_criticality AS STRING)) IN ('nao', 'no', 'false') THEN 'a. No'
            WHEN LOWER(CAST(es.talent_criticality AS STRING)) IN ('sim', 'yes', 'true') THEN 'b. Yes'
            ELSE NULL
        END AS criticidade,
        CASE
            WHEN es.perf_composite_score IS NULL AND es.perf_final_range IS NULL THEN NULL
            WHEN LOWER(CAST(es.perf_final_range AS STRING)) LIKE '%insufficient%' THEN 'a. Insufficient'
            WHEN LOWER(CAST(es.perf_final_range AS STRING)) LIKE '%partially%' THEN 'b. Partially misses expectations'
            WHEN LOWER(CAST(es.perf_final_range AS STRING)) LIKE '%meets%' THEN 'c. Meets expectations'
            WHEN LOWER(CAST(es.perf_final_range AS STRING)) LIKE '%above%' THEN 'd. Above expectations'
            WHEN LOWER(CAST(es.perf_final_range AS STRING)) LIKE '%outstanding%' THEN 'e. Outstanding'
            WHEN es.perf_composite_score < 70 THEN 'a. Insufficient'
            WHEN es.perf_composite_score BETWEEN 70 AND 89 THEN 'b. Partially misses expectations'
            WHEN es.perf_composite_score BETWEEN 90 AND 109 THEN 'c. Meets expectations'
            WHEN es.perf_composite_score >= 110 AND es.perf_composite_score <= 120 THEN 'd. Above expectations'
            WHEN es.perf_composite_score >= 121 THEN 'e. Outstanding'
            ELSE NULL
        END AS perf_final,
        CASE
            WHEN es.highest_education_level IS NULL THEN NULL
            WHEN LOWER(TRIM(es.highest_education_level)) IN ('nao informado', 'não informado', 'not informed') THEN NULL
            WHEN LOWER(es.highest_education_level) LIKE '%incomplet%' THEN
                CASE
                    WHEN LOWER(es.highest_education_level) LIKE '%fundamental%'
                        OR LOWER(es.highest_education_level) LIKE '%medio%'
                        OR LOWER(es.highest_education_level) LIKE '%middle school%' THEN 'a. Middle school'
                    WHEN LOWER(es.highest_education_level) LIKE '%tecnico%'
                        OR LOWER(es.highest_education_level) LIKE '%tecnologo%'
                        OR LOWER(es.highest_education_level) LIKE '%technical%'
                        OR LOWER(es.highest_education_level) LIKE '%superior%'
                        OR LOWER(es.highest_education_level) LIKE '%university%' THEN 'b. High school'
                    WHEN LOWER(es.highest_education_level) LIKE '%pos%'
                        OR LOWER(es.highest_education_level) LIKE '%post%' THEN 'd. Graduate degree'
                    WHEN LOWER(es.highest_education_level) LIKE '%mestrado%'
                        OR LOWER(es.highest_education_level) LIKE '%master%' THEN 'f. Master''s degree'
                    WHEN LOWER(es.highest_education_level) LIKE '%doutorado%'
                        OR LOWER(es.highest_education_level) LIKE '%doctor%' THEN 'g. Doctorate degree'
                    ELSE NULL
                END
            WHEN LOWER(es.highest_education_level) LIKE '%middle school%'
                OR LOWER(es.highest_education_level) LIKE '%fundamental%' THEN 'a. Middle school'
            WHEN LOWER(es.highest_education_level) LIKE '%high school%'
                OR LOWER(es.highest_education_level) LIKE '%medio completo%'
                OR LOWER(es.highest_education_level) LIKE '%higher university%' THEN 'b. High school'
            WHEN LOWER(es.highest_education_level) LIKE '%technical%'
                OR LOWER(es.highest_education_level) LIKE '%tecnico completo%'
                OR LOWER(es.highest_education_level) LIKE '%tecnologo completo%'
                OR LOWER(es.highest_education_level) LIKE '%vocational%'
                OR LOWER(es.highest_education_level) LIKE '%completion of a vocational%' THEN 'c. Technical degree'
            WHEN LOWER(es.highest_education_level) LIKE '%superior completa%'
                OR LOWER(es.highest_education_level) LIKE '%specialized college%' THEN 'd. Graduate degree'
            WHEN LOWER(es.highest_education_level) LIKE '%postgraduate%'
                OR LOWER(es.highest_education_level) LIKE '%pos-graduacao completa%'
                OR LOWER(es.highest_education_level) LIKE '%postgraduate specialization%'
                OR LOWER(es.highest_education_level) LIKE '%pos doutorado%' THEN 'e. Postgraduate degree'
            WHEN LOWER(es.highest_education_level) LIKE '%mestrado completo%'
                OR (
                    LOWER(es.highest_education_level) LIKE '%master%'
                    AND LOWER(es.highest_education_level) NOT LIKE '%post%'
                ) THEN 'f. Master''s degree'
            WHEN LOWER(es.highest_education_level) LIKE '%doutorado completo%'
                OR LOWER(es.highest_education_level) LIKE '%pos doutorado%'
                OR (
                    LOWER(es.highest_education_level) LIKE '%doctor%'
                    AND LOWER(es.highest_education_level) NOT LIKE '%incomplet%'
                ) THEN 'g. Doctorate degree'
            ELSE NULL
        END AS escolaridade,
        CASE
            WHEN es.consolidated_business_unit_name NOT IN (
                'QuintoAndar SP',
                'QuintoAndar SC',
                'QuintoAndar MG'
            ) THEN NULL
            WHEN es.amount_salary < 2001 THEN '1. Less than 2001 BRL'
            WHEN es.amount_salary BETWEEN 2001 AND 4000 THEN '2. From 2001 to 4000 BRL'
            WHEN es.amount_salary BETWEEN 4001 AND 6000 THEN '3. From 4001 to 6000 BRL'
            WHEN es.amount_salary BETWEEN 6001 AND 10000 THEN '4. From 6001 to 10000 BRL'
            WHEN es.amount_salary BETWEEN 10001 AND 15000 THEN '5. From 10001 to 15000 BRL'
            WHEN es.amount_salary BETWEEN 15001 AND 20000 THEN '6. From 15001 to 20000 BRL'
            WHEN es.amount_salary BETWEEN 20001 AND 30000 THEN '7. From 20001 to 30000 BRL'
            WHEN es.amount_salary > 30000 THEN '8. Over 30000 BRL'
            ELSE NULL
        END AS faixa_salarial,
        CASE
            WHEN TRY_CAST(es.band AS DOUBLE) BETWEEN 1 AND 3 THEN 'a. Bands 1-3'
            WHEN TRY_CAST(es.band AS DOUBLE) BETWEEN 4 AND 6 THEN 'b. Bands 4-6'
            WHEN TRY_CAST(es.band AS DOUBLE) BETWEEN 7 AND 8 THEN 'c. Bands 7-8'
            WHEN TRY_CAST(es.band AS DOUBLE) BETWEEN 9 AND 11 THEN 'd. Bands 9-11'
            WHEN TRY_CAST(es.band AS DOUBLE) >= 12 THEN 'e. Bands 12+'
            ELSE NULL
        END AS grupo_banda,
        CASE
            WHEN li.index_count >= 30 THEN LOWER(es.email_l1)
            ELSE NULL
        END AS l1_e,
        LOWER(es.email_l2) AS l2_e,
        CASE
            WHEN lb3.band IS NOT NULL THEN LOWER(es.email_l3)
            ELSE NULL
        END AS l3_e,
        CASE
            WHEN lb4.band IS NOT NULL THEN LOWER(es.email_l4)
            ELSE NULL
        END AS l4_e,
        CASE
            WHEN lb5.band IS NOT NULL THEN LOWER(es.email_l5)
            ELSE NULL
        END AS l5_e,
        LOWER(COALESCE(es.hrbp_work_email, cc_current.hrbp_work_email)) AS hrbp,
        CONCAT(
            '-',
            CONCAT_WS(
                '-',
                CASE
                    WHEN li.index_count >= 30 THEN LOWER(es.email_l1)
                    ELSE NULL
                END,
                LOWER(es.email_l2),
                CASE
                    WHEN lb3.band IS NOT NULL THEN LOWER(es.email_l3)
                    ELSE NULL
                END,
                CASE
                    WHEN lb4.band IS NOT NULL THEN LOWER(es.email_l4)
                    ELSE NULL
                END,
                CASE
                    WHEN lb5.band IS NOT NULL THEN LOWER(es.email_l5)
                    ELSE NULL
                END,
                LOWER(COALESCE(es.hrbp_work_email, cc_current.hrbp_work_email))
            ),
            rc.access_list_roles
        ) AS access_list,
        CONCAT(
            '-',
            CONCAT_WS(
                '-',
                LOWER(es.email_l1),
                LOWER(es.email_l2),
                LOWER(es.email_l3),
                LOWER(es.email_l4),
                LOWER(es.email_l5),
                LOWER(es.email_l6),
                LOWER(es.email_l7),
                LOWER(es.email_l8),
                LOWER(COALESCE(es.hrbp_work_email, cc_current.hrbp_work_email))
            ),
            rc.access_list_roles
        ) AS access_list_all_leaders,
        LOWER(es.status) AS status
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
        l1_index AS li
            ON LOWER(es.email_l1) = li.l1_e
            AND es.dt_month_reference = li.fechamento
    LEFT JOIN
        leader_band AS lb3
            ON LOWER(es.email_l3) = lb3.email
            AND lb3.band >= 11
    LEFT JOIN
        leader_band AS lb4
            ON LOWER(es.email_l4) = lb4.email
            AND lb4.band >= 11
    LEFT JOIN
        leader_band AS lb5
            ON LOWER(es.email_l5) = lb5.email
            AND lb5.band >= 11
    CROSS JOIN
        roles_concatenados AS rc
    WHERE
        es.is_primary_assignment_for_snapshot = TRUE
        AND es.dt_month_reference >= MAKE_DATE(YEAR(DATE('{load_start_date}')) - 2, 12, 31)
)
SELECT
    bi.fechamento,
    bi.empresa,
    bi.pais,
    bi.vertical,
    bi.structure,
    bi.team,
    bi.pwd,
    bi.bim,
    bi.women,
    bi.lgbt,
    bi.urg,
    bi.faixa_etaria,
    bi.tenure,
    bi.diretos,
    bi.classe_cargo,
    bi.fl_lider,
    bi.potencial,
    bi.criticidade,
    bi.perf_final,
    bi.escolaridade,
    bi.faixa_salarial,
    bi.grupo_banda,
    bi.l1_e,
    bi.l2_e,
    bi.l3_e,
    bi.l4_e,
    bi.l5_e,
    bi.hrbp,
    bi.access_list,
    bi.access_list_all_leaders,
    SUM(CASE WHEN bi.status IN ('active', 'ativo') THEN 1 ELSE 0 END) AS ativos,
    SUM(
        CASE
            WHEN bi.status IN ('terminated', 'desligamento', 'desligado') THEN 1
            ELSE 0
        END
    ) AS desligamentos,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    base_inicial AS bi
GROUP BY
    bi.fechamento,
    bi.empresa,
    bi.pais,
    bi.vertical,
    bi.structure,
    bi.team,
    bi.pwd,
    bi.bim,
    bi.women,
    bi.lgbt,
    bi.urg,
    bi.faixa_etaria,
    bi.tenure,
    bi.diretos,
    bi.classe_cargo,
    bi.fl_lider,
    bi.potencial,
    bi.criticidade,
    bi.perf_final,
    bi.escolaridade,
    bi.faixa_salarial,
    bi.grupo_banda,
    bi.l1_e,
    bi.l2_e,
    bi.l3_e,
    bi.l4_e,
    bi.l5_e,
    bi.hrbp,
    bi.access_list,
    bi.access_list_all_leaders
