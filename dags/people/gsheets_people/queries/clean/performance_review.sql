SELECT 
    nome AS name,
    impacto AS impact,
    email,
    comportamento AS behavior,
    lideranca AS leadership,
    faixa_de_distribuicao AS distribution_range,
    comentario_gestor AS comment_manager,
    ciclo AS cycle,
    email_avaliador AS evaluator_email,
    calibracao_impacto AS calibration_impact,
    calibracao_comportamento AS calibration_behavior,
    calibracao_lideranca AS calibration_leadership,
    genero AS gender,
    orientacao_sexual AS sexual_orientation,
    sexo AS sex,
    raca AS ethnicity,
    faixa_etaria AS age_range,
    tenure,
    classe_cargo AS position_class,
    banda AS band,
    centro_de_custo AS cost_center,
    sub_diretoria AS sub_board,
    diretoria AS board,
    vice_presidencia AS vice_presidency,
    vertical,
    pais AS country,
    performance_score,
    CASE 
        WHEN pcd = 'sim'
            THEN TRUE
        ELSE FALSE
    END AS has_disabilty,
    CASE 
        WHEN status = 'ativo'
            THEN TRUE
        ELSE FALSE
    END AS is_active,
    ts_load
FROM datalake_gsheets_people_raw.performance_review