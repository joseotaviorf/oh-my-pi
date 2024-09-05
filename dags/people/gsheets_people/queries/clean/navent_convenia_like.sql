SELECT
    UPPER(id_colaborador) AS assignment_number,
    id_navent,
    person_number,
    UPPER(id_gestor) AS manager_assignment_number,
    empresa AS company,
    email AS employee_email,
    email_navent AS employee_email_navent,
    nome AS employee_name,
    status AS employee_status,
    cargo AS employee_position,
    classe_cargo AS employee_position_class,
    gestor AS employee_manager,
    nacionalidade AS employee_nacionality,
    motivo_desligamento AS employee_dismissal_reason,
    sexo AS employee_sex,
    centro_de_custo AS employee_cost_center,
    sub_diretoria AS employee_sub_directorate,
    diretoria AS employee_directorate,
    vice_presidencia AS employee_vice_presidency,
    vertical AS employee_vertical,
    marca_produto_dedicado AS employee_product_brand,
    business_navent AS employee_business_navent,
    pais AS employee_country,
    hrbp AS employee_hbrp,
    banda AS employee_band,
    cod_cargo AS employee_job_code,
    naturalidade_cidade AS employee_birth_city,
    restricciones_alimentarias AS employee_dietary_restrictions,
    residencia_pais AS employee_resident_country,
    origen_etnico AS employee_ethnicity,
    identidade_genero AS employee_gender_identity,
    orientacao_sexual AS employee_sexual_orientation,
    tipo_deficiencia AS employee_disability_type,
    neurodiversidade AS employee_neurodiversity,
    estado_civil AS employee_marital_status,
    religiosidade AS employee_religion,
    tipo_de_vivienda AS employee_housing_type,
    potencial AS employee_potential,
    criticidade AS employee_criticality,
    faixa_etaria AS employee_age_range,
    email_gestor AS manager_email,
    email_left,
    situacion_en_el_pais AS employee_country_situation,
    tenure,
    UPPER(SPLIT(salario_moeda_local, ' ')[0]) AS currency,
    DOUBLE(SPLIT(salario_moeda_local,' ')[1]) AS salary_local_currency,
    DOUBLE(salario) AS salary,
    CASE
        WHEN fl_lider = 1
            THEN TRUE
        ELSE FALSE
    END AS is_leader,
    CASE
      WHEN status_gestor = 'ativo'
        THEN TRUE
      ELSE FALSE
    END AS is_manager_active,
    INT(idade_pessoa) AS employee_age,
    CASE
      WHEN contains(dt_inicio, '/')
        THEN TO_DATE(dt_inicio, 'M/d/yyyy')
      ELSE date(dt_inicio)
    END AS dt_start,
    CASE
      WHEN contains(dt_desligamento, '/')
        THEN TO_DATE(dt_desligamento, 'M/d/yyyy')
      ELSE date(dt_desligamento)
    END AS dt_dismissal,
    TO_DATE(dt_nascimento, 'M/d/yyyy') AS dt_birth,
    NOW() AS ts_load
FROM datalake_gsheets_raw.navent_convenia_like