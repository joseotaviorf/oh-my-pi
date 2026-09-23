-- Full employee roster for People Insights (tab base_completa_grupo).
WITH social_names AS (
    SELECT DISTINCT
        im.person_number,
        pn.first_social_name,
        pn.last_social_name
    FROM
        datalake_people.identifier_mapping AS im
    INNER JOIN
        datalake_pin_core_clean.person_name AS pn
            ON pn.id_person = im.id_person
            AND pn.name_type = 'GLOBAL'
            AND pn.dt_effective_ended = DATE('9999-12-31')
    WHERE
        NOT im.is_user_test
        AND (pn.first_social_name IS NOT NULL OR pn.last_social_name IS NOT NULL)
)
SELECT
    bu.consolidated_business_unit_name AS empresa,
    LOWER(es.assignment_number) AS id_colaborador,
    LOWER(es.name) AS nome,
    es.person_number AS matricula,
    LOWER(es.work_email) AS email,
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END AS status,
    LOWER(es.band) AS banda,
    LOWER(es.manager_assignment_number) AS id_gestor,
    LOWER(es.manager_name) AS gestor,
    LOWER(es.job_name) AS cargo,
    LOWER(es.job_family) AS classe_cargo,
    LOWER(es.cost_center_code) AS numero_centro_de_custo,
    CONCAT(
        LOWER(es.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(es.cost_center_name), 10)
    ) AS centro_de_custo,
    NULLIF(LOWER(es.owner_l1_name), '-1') AS l1_cc,
    NULLIF(LOWER(es.owner_l2_name), '-1') AS l2_cc,
    NULLIF(LOWER(es.owner_l3_name), '-1') AS l3_cc,
    NULLIF(LOWER(es.vertical), '-1') AS vertical,
    NULLIF(LOWER(es.structure), '-1') AS structure,
    NULLIF(LOWER(es.team), '-1') AS team,
    NULLIF(LOWER(es.business), '-1') AS business,
    NULLIF(LOWER(es.product), '-1') AS product,
    NULLIF(LOWER(es.brand), '-1') AS brand,
    NULLIF(LOWER(es.chapter), '-1') AS chapter,
    NULLIF(LOWER(es.line), '-1') AS line,
    LOWER(COALESCE(es.hrbp_work_email, cc_current.hrbp_work_email)) AS hrbp,
    es.business_unit_name AS marca_produto_dedicado,
    CASE
        WHEN es.manager_is_active IS TRUE THEN 'ativo'
        WHEN es.manager_is_active IS FALSE THEN 'desligado'
        ELSE NULL
    END AS status_gestor,
    CAST(es.count_direct_report AS DOUBLE) AS diretos,
    CAST(es.count_total_report AS DOUBLE) AS diretos_e_indiretos,
    CAST(es.hierarchy_depth AS DOUBLE) AS layer,
    CASE
        WHEN es.is_manager IS TRUE THEN 1
        ELSE 0
    END AS fl_lider,
    LOWER(es.personal_email) AS email_pessoal,
    es.dt_employee_hired AS dt_inicio,
    es.dt_terminated AS dt_desligamento,
    CASE
        WHEN LOWER(es.termination_type) = 'voluntary' THEN 'voluntario'
        WHEN LOWER(es.termination_type) = 'involuntary' THEN 'involuntario'
        ELSE LOWER(es.termination_type)
    END AS motivo_desligamento,
    CASE
        WHEN es.registered_sex IS NULL THEN 'nao especificado'
        WHEN LOWER(es.registered_sex) = 'male' THEN 'masculino'
        WHEN LOWER(es.registered_sex) = 'female' THEN 'feminino'
        ELSE LOWER(es.registered_sex)
    END AS sexo,
    es.dt_birth AS dt_nascimento,
    CASE
        WHEN es.amount_salary IS NULL OR CAST(es.amount_salary AS DOUBLE) < 1 THEN CAST(NULL AS STRING)
        ELSE FORMAT_STRING('%.2f', CAST(es.amount_salary AS DOUBLE))
    END AS salario,
    CASE LOWER(es.marital_status)
        WHEN 'solteiro' THEN 'soltero/a'
        WHEN 'solteira' THEN 'soltero/a'
        WHEN 'single' THEN 'soltero/a'
        WHEN 'casado' THEN 'casado(a)'
        WHEN 'casada' THEN 'casado(a)'
        WHEN 'married' THEN 'casado(a)'
        WHEN 'divorciado' THEN 'divorciado(a)'
        WHEN 'divorciada' THEN 'divorciado(a)'
        WHEN 'divorced' THEN 'divorciado(a)'
        WHEN 'viuvo' THEN 'viuvo(a)'
        WHEN 'viuva' THEN 'viuvo(a)'
        WHEN 'widowed' THEN 'viuvo(a)'
        WHEN '-1' THEN NULL
        ELSE LOWER(es.marital_status)
    END AS estado_civil,
    CASE LOWER(es.gender_identity)
        WHEN 'man cisgender' THEN 'homem cis'
        WHEN 'woman cisgender' THEN 'mulher cis'
        WHEN 'non-binary' THEN 'nao binario'
        WHEN 'non binary' THEN 'nao binario'
        WHEN 'transgender man' THEN 'homem trans'
        WHEN 'transgender woman' THEN 'mulher trans'
        WHEN 'prefer not to inform' THEN 'prefiro nao informar'
        WHEN 'prefer not to answer' THEN 'prefiro nao informar'
        WHEN 'i prefer not to say' THEN 'prefiro nao informar'
        WHEN 'prefer not to say' THEN 'prefiro nao informar'
        WHEN '-1' THEN NULL
        ELSE LOWER(es.gender_identity)
    END AS identidade_genero,
    CASE LOWER(es.employment_type)
        WHEN 'young apprentice' THEN 'jovem aprendiz'
        WHEN 'intern' THEN 'estagiario'
        WHEN 'clt' THEN 'clt'
        ELSE LOWER(es.employment_type)
    END AS vinculo,
    CASE LOWER(es.ethnicity)
        WHEN 'white' THEN 'branca'
        WHEN 'black' THEN 'preta'
        WHEN 'black or african american' THEN 'preta'
        WHEN 'african american' THEN 'preta'
        WHEN 'brown' THEN 'parda'
        WHEN 'yellow' THEN 'amarela'
        WHEN 'indigenous' THEN 'indigena'
        WHEN 'two or more races' THEN 'parda'
        WHEN 'not informed' THEN NULL
        WHEN 'prefer not to inform' THEN NULL
        WHEN "i'd rather not answer" THEN NULL
        WHEN '-1' THEN NULL
        ELSE LOWER(es.ethnicity)
    END AS raca,
    COALESCE(es.cpf, doc.cpf) AS cpf,
    LOWER(es.rg) AS rg,
    TRIM(LOWER(es.address_street)) AS residencia_endereco,
    LOWER(es.address_number) AS residencia_numero,
    NULLIF(
        TRIM(regexp_replace(LOWER(es.address_complement), ' +', ' ')),
        ''
    ) AS residencia_complemento,
    LOWER(es.address_zip_code) AS residencia_cep,
    LOWER(es.address_state) AS residencia_uf,
    REGEXP_REPLACE(LOWER(es.address_city), '\u00A0', ' ') AS residencia_cidade,
    TRIM(LOWER(es.address_district)) AS residencia_bairro,
    CASE LOWER(es.highest_education_level)
        WHEN 'completion of a vocational school course' THEN 'ensino medio completo'
        WHEN 'secondary vocational education' THEN 'ensino medio incompleto'
        WHEN 'high school graduate' THEN 'ensino medio completo'
        WHEN 'some high school' THEN 'ensino medio incompleto'
        WHEN 'college/university degree' THEN 'educacao superior completa'
        WHEN 'some college/university courses' THEN 'educacao superior incompleta'
        WHEN 'post-graduate diploma' THEN 'pos-graduacao completa'
        WHEN 'master degree' THEN 'pos-graduacao completa'
        WHEN 'doctorate' THEN 'pos-graduacao completa'
        ELSE LOWER(es.highest_education_level)
    END AS formacao_escolaridade,
    CAST(MONTH(es.dt_employee_hired) AS DOUBLE) AS mes_aniv_empresa,
    CAST(DAY(es.dt_employee_hired) AS INT) AS dia_aniversario_empresa,
    CASE
        WHEN MONTH(es.dt_employee_hired) = MONTH(DATE('{load_start_date}')) THEN 1
        ELSE 0
    END AS fl_mes_aniversario_empresa,
    CAST(MONTH(es.dt_birth) AS DOUBLE) AS mes_aniv_pessoal,
    CAST(DAY(es.dt_birth) AS INT) AS dia_aniversario_pessoa,
    CASE
        WHEN es.dt_birth IS NULL THEN NULL
        WHEN MONTH(es.dt_birth) = MONTH(DATE('{load_start_date}')) THEN 1
        ELSE 0
    END AS fl_mes_aniversario_pessoa,
    CAST(es.age_in_years AS DOUBLE) AS idade_pessoa,
    CAST(es.months_employee_tenure AS INT) AS idade_empresa,
    CASE
        WHEN es.age_in_years IS NULL THEN NULL
        WHEN CAST(es.age_in_years AS INT) < 21 THEN 'a. menos de 21 anos'
        WHEN CAST(es.age_in_years AS INT) BETWEEN 21 AND 25 THEN 'b. de 21 ate 25 anos'
        WHEN CAST(es.age_in_years AS INT) BETWEEN 26 AND 30 THEN 'c. de 26 ate 30 anos'
        WHEN CAST(es.age_in_years AS INT) BETWEEN 31 AND 35 THEN 'd. de 31 ate 35 anos'
        WHEN CAST(es.age_in_years AS INT) BETWEEN 36 AND 40 THEN 'e. de 36 ate 40 anos'
        WHEN CAST(es.age_in_years AS INT) BETWEEN 41 AND 45 THEN 'f. de 41 ate 45 anos'
        ELSE 'g. mais de 45 anos'
    END AS faixa_etaria,
    CASE
        WHEN es.months_employee_tenure IS NULL THEN NULL
        WHEN CAST(es.months_employee_tenure AS INT) < 3 THEN 'a. menos de 3 meses'
        WHEN CAST(es.months_employee_tenure AS INT) < 6 THEN 'b. 3 a 5 meses'
        WHEN CAST(es.months_employee_tenure AS INT) < 13 THEN 'c. 6 a 12 meses'
        WHEN CAST(es.months_employee_tenure AS INT) < 19 THEN 'd. 13 a 18 meses'
        WHEN CAST(es.months_employee_tenure AS INT) < 25 THEN 'e. 19 a 24 meses'
        WHEN CAST(es.months_employee_tenure AS INT) < 37 THEN 'f. 25 a 36 meses'
        ELSE 'g. mais de 36 meses'
    END AS tenure,
    CASE
        WHEN es.amount_salary IS NULL OR CAST(es.amount_salary AS DOUBLE) < 1 THEN NULL
        WHEN CAST(es.amount_salary AS DOUBLE) < 2001 THEN '1. menos de 2001 reais'
        WHEN CAST(es.amount_salary AS DOUBLE) <= 4000 THEN '2. de 2001 ate 4000 reais'
        WHEN CAST(es.amount_salary AS DOUBLE) <= 6000 THEN '3. de 4001 ate 6000 reais'
        WHEN CAST(es.amount_salary AS DOUBLE) <= 8000 THEN '4. de 6001 ate 8000 reais'
        WHEN CAST(es.amount_salary AS DOUBLE) <= 10000 THEN '5. de 8001 ate 10000 reais'
        WHEN CAST(es.amount_salary AS DOUBLE) <= 15000 THEN '6. de 10001 ate 15000 reais'
        WHEN CAST(es.amount_salary AS DOUBLE) <= 20000 THEN '7. de 15001 ate 20000 reais'
        WHEN CAST(es.amount_salary AS DOUBLE) <= 25000 THEN '8. de 20001 ate 25000 reais'
        ELSE '9. mais de 25000 reais'
    END AS faixa_salario,
    CAST(es.last_raise_amount AS DOUBLE) AS ult_aumento,
    CAST(es.last_raise_pct AS DOUBLE) AS ult_aumento_pct,
    LOWER(es.last_raise_reason) AS motivo_ult_aumento,
    es.dt_last_raise AS dt_ultimo_aumento,
    CAST(es.months_since_last_raise AS DOUBLE) AS recency,
    CASE
        WHEN es.salary_midpoint_ratio IS NULL THEN CAST(NULL AS STRING)
        ELSE FORMAT_STRING('%.3f', CAST(es.salary_midpoint_ratio AS DOUBLE))
    END AS pos_faixa,
    CAST(es.salary_range_mid AS DOUBLE) AS referencia,
    es.has_clock_in AS registra_ponto,
    CASE
        WHEN es.full_phone_number IS NULL OR TRIM(es.full_phone_number) = '' THEN NULL
        WHEN es.full_phone_number LIKE '+%' THEN es.full_phone_number
        ELSE CONCAT('+', es.full_phone_number)
    END AS numero_celular,
    CASE
        WHEN es.is_eligible_internet_reimbursement IS TRUE THEN 'sim'
        WHEN es.is_eligible_internet_reimbursement IS FALSE THEN 'nao'
        ELSE 'nao'
    END AS elig_reemb_internet,
    es.talent_potential AS potencial,
    es.talent_criticality AS criticidade,
    es.development_matrix AS matriz_de_desenvolvimento,
    CASE
        WHEN es.is_layoff IS TRUE THEN 'sim'
        WHEN es.is_layoff IS FALSE THEN 'nao'
        ELSE NULL
    END AS layoffs,
    CASE LOWER(es.sexual_orientation)
        WHEN 'heterosexual' THEN '3 - heterossexual'
        WHEN 'bisexual' THEN '2 - bissexual'
        WHEN 'homosexual' THEN '4 - homossexual'
        WHEN 'gay' THEN '4 - homossexual'
        WHEN 'lesbian' THEN '4 - homossexual'
        WHEN 'pansexual' THEN '5 - pansexual'
        WHEN 'asexual' THEN '6 - assexual'
        WHEN 'prefer not to inform' THEN '7 - prefiro nao informar'
        WHEN 'prefer not to answer' THEN '7 - prefiro nao informar'
        WHEN "i'd rather not answer" THEN '7 - prefiro nao informar'
        WHEN '-1' THEN NULL
        ELSE LOWER(es.sexual_orientation)
    END AS orientacao_sexual,
    CASE LOWER(translate(es.religion, 'ÁÀÃÂÄÉÊËÍÎÓÔÕÖÚÜÇÑ', 'AAAAAEEEIIOOOOUUCN'))
        WHEN '-1' THEN NULL
        WHEN 'prefer not to inform' THEN 'prefiro nao informar'
        WHEN 'prefer not to answer' THEN 'prefiro nao informar'
        WHEN "i'd rather not answer" THEN 'prefiro nao informar'
        WHEN 'i prefer not to say' THEN 'prefiro nao informar'
        WHEN 'no religion' THEN 'sem religiao'
        WHEN 'atheist' THEN 'ateismo'
        WHEN 'agnostic' THEN 'agnosticismo'
        WHEN 'christianity' THEN 'cristianismo'
        WHEN 'catholicism' THEN 'catolicismo'
        WHEN 'catholicism/christianity' THEN 'catolicismo'
        WHEN 'evangelicalism' THEN 'evangelismo'
        WHEN 'protestantism' THEN 'evangelismo'
        WHEN 'spiritism' THEN 'espiritismo'
        WHEN 'umbanda' THEN 'umbanda'
        WHEN 'candomble' THEN 'candomble'
        WHEN 'candomblé' THEN 'candomble'
        WHEN 'judaism' THEN 'judaismo'
        WHEN 'islam' THEN 'islamismo'
        WHEN 'buddhism' THEN 'budismo'
        WHEN 'hinduism' THEN 'hinduismo'
        ELSE LOWER(es.religion)
    END AS religiosidade,
    CASE LOWER(es.neurodiversity)
        WHEN "i'm not a neuro minority person" THEN 'neurotipico/a'
        ELSE LOWER(es.neurodiversity)
    END AS neurodiversidade,
    CASE LOWER(COALESCE(dis.category, es.documented_disability_name))
        WHEN 'motor deficiency' THEN 'deficiencia fisica'
        WHEN 'sensory deficiency' THEN 'deficiencia sensorial'
        WHEN 'hearing deficiency' THEN 'deficiencia auditiva'
        WHEN 'hearing impairment' THEN 'deficiencia auditiva'
        WHEN 'visual deficiency' THEN 'deficiencia visual'
        WHEN 'intellectual deficiency' THEN 'deficiencia intelectual'
        WHEN 'multiple deficiencies' THEN 'deficiencia multipla'
        ELSE LOWER(COALESCE(dis.category, es.documented_disability_name))
    END AS tipo_deficiencia,
    CASE
        WHEN dis.is_active IS TRUE OR es.has_self_declared_pwd IS TRUE THEN 'sim'
        ELSE 'nao'
    END AS pcd,
    NULLIF(
        LOWER(TRIM(CONCAT_WS(' ', sn.first_social_name, sn.last_social_name))),
        ''
    ) AS nome_social,
    CASE
        WHEN es.is_manager IS TRUE THEN 'lider'
        ELSE 'nao lider'
    END AS lideranca,
    CAST(FROM_UTC_TIMESTAMP(es.ts_load, 'America/Sao_Paulo') AS STRING) AS dt_last_update,
    CASE
        WHEN dis.is_active IS TRUE OR es.has_medical_disability_record IS TRUE THEN 'sim'
        ELSE 'nao'
    END AS pcd_laudo,
    LOWER(es.name_l1) AS l1_gestor,
    LOWER(es.name_l2) AS l2_gestor,
    CASE es.country
        WHEN 'Brazil' THEN 'brasil'
        WHEN 'Argentina' THEN 'argentina'
        WHEN 'Mexico' THEN 'mexico'
        WHEN 'Portugal' THEN 'portugal'
        WHEN 'Peru' THEN 'peru'
        WHEN 'Uruguay' THEN 'uruguai'
        WHEN 'Ecuador' THEN 'ecuador'
        WHEN 'United States' THEN 'estados unidos'
        WHEN 'Panama' THEN 'panama'
        ELSE LOWER(es.country)
    END AS pais,
    LOWER(es.address_country) AS residencia_pais,
    CASE
        WHEN bu.consolidated_business_unit_name = 'Classifieds'
            AND LOWER(es.ethnicity) NOT IN ('-1', 'not informed', 'prefer not to inform')
            AND es.ethnicity IS NOT NULL
        THEN CASE LOWER(es.ethnicity)
            WHEN 'white' THEN 'Branca'
            WHEN 'black' THEN 'Preta'
            WHEN 'black or african american' THEN 'Preta'
            WHEN 'brown' THEN 'Parda'
            WHEN 'yellow' THEN 'Amarela'
            WHEN 'indigenous' THEN 'Indigena'
            WHEN 'two or more races' THEN 'Parda'
            ELSE es.ethnicity
        END
        ELSE CAST(NULL AS STRING)
    END AS origen_etnico,
    NULLIF(
        CASE
            WHEN comp_job.target_plr_salary_multiplier > 0
            THEN CAST(comp_job.target_plr_salary_multiplier AS DOUBLE)
            ELSE CAST(comp_job.target_plr AS DOUBLE)
        END,
        0
    ) AS target_rv,
    LOWER(es.salary_table) AS tabela_salarial,
    CASE
        WHEN es.is_executive_team_member IS TRUE THEN 'ET'
        ELSE CAST(NULL AS STRING)
    END AS fl_et,
    CASE
        WHEN CAST(es.band AS INT) >= 10 THEN 'LT'
        ELSE CAST(NULL AS STRING)
    END AS fl_lt,
    CASE
        WHEN comp_job.is_leadership_job IS TRUE THEN 'l'
        WHEN comp_job.is_leadership_job IS FALSE THEN 'ci'
        ELSE NULL
    END AS trilha,
    CASE
        WHEN CAST(es.perf_impact_score AS DOUBLE) IS NULL THEN NULL
        WHEN CAST(es.perf_impact_score AS DOUBLE) < 90 THEN 'd. partially misses expectations'
        WHEN CAST(es.perf_impact_score AS DOUBLE) < 110 THEN 'c. meets expectations'
        WHEN CAST(es.perf_impact_score AS DOUBLE) <= 137 THEN 'b. above expectations'
        ELSE 'a. outstanding'
    END AS impacto,
    CASE
        WHEN CAST(es.perf_behavior_score AS DOUBLE) IS NULL THEN NULL
        WHEN CAST(es.perf_behavior_score AS DOUBLE) < 90 THEN 'd. partially misses expectations'
        WHEN CAST(es.perf_behavior_score AS DOUBLE) < 110 THEN 'c. meets expectations'
        WHEN CAST(es.perf_behavior_score AS DOUBLE) <= 137 THEN 'b. above expectations'
        ELSE 'a. outstanding'
    END AS comportamento,
    CASE
        WHEN CAST(es.perf_leadership_score AS DOUBLE) IS NULL THEN NULL
        WHEN CAST(es.perf_leadership_score AS DOUBLE) < 90 THEN 'd. partially misses expectations'
        WHEN CAST(es.perf_leadership_score AS DOUBLE) < 110 THEN 'c. meets expectations'
        WHEN CAST(es.perf_leadership_score AS DOUBLE) <= 137 THEN 'b. above expectations'
        ELSE 'a. outstanding'
    END AS lideranca_pr,
    CAST(es.perf_composite_score AS DOUBLE) AS performance_score,
    CASE LOWER(es.perf_final_range)
        WHEN 'exceeds expectations' THEN 'a. outstanding'
        WHEN 'outstanding' THEN 'a. outstanding'
        WHEN 'above expectations' THEN 'b. above expectations'
        WHEN 'meets expectations' THEN 'c. meets expectations'
        WHEN 'partially misses expectations' THEN 'd. partially misses expectations'
        WHEN 'misses expectations' THEN 'e. misses expectations'
        WHEN 'does not meet expectations' THEN 'e. misses expectations'
        ELSE LOWER(es.perf_final_range)
    END AS faixa_pr,
    es.talent_readiness AS prontidao,
    es.talent_risk_of_loss AS risco_de_perda,
    LOWER(es.manager_work_email) AS email_gestor,
    es.dt_employee_hired AS dt_inicio_person,
    CASE
        WHEN es.is_executive_team_member IS TRUE THEN 'ET'
        ELSE CAST(NULL AS STRING)
    END AS et,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
LEFT JOIN
    dw_employee_details.dim_documentation AS doc
        ON doc.person_number = es.person_number
        AND doc.is_current = TRUE
LEFT JOIN
    dw_demographics.dim_employee_disability AS dis
        ON dis.sk_employee = es.sk_employee
        AND dis.is_primary = TRUE
        AND DATE('{load_start_date}') >= dis.dt_valid_from
        AND DATE('{load_start_date}') <= dis.dt_valid_to
LEFT JOIN
    dw_compensation.dim_job AS comp_job
        ON comp_job.sk_job_version = es.sk_job_version
LEFT JOIN
    social_names AS sn
        ON sn.person_number = es.person_number
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON cc.sk_cost_center_version = es.sk_cost_center_version
LEFT JOIN
    dw_organization.dim_cost_center AS cc_current
        ON cc_current.id_organization = cc.id_organization
        AND cc_current.is_current = TRUE
WHERE
    es.is_current_for_employee = TRUE
