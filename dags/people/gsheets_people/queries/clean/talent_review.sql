SELECT
    ciclo AS cycle,
    email,
    email_avaliador AS evaluator_email,
    prontidao AS readiness,
    risco_de_perda AS loss_risk,
    potencial AS potential,
    criticidade AS criticality,
    evo_potencial AS evolution_potential,
    evo_criticidade AS evolution_criticality,
    evo_risco_de_perda AS evolution_loss_risk,
    evo_prontidao AS evolution_readiness,
    ult_ciclo_avaliado AS last_cycle_evaluated,
    ciclo_novo_padrao AS new_standard_cycle,
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
    empresa AS company,
    geracao AS generation,
    l1_n,
    l2_n,
    l3_n,
    l4_n,
    l5_n,
    l6_n,
    l7_n,
    email_gestor AS manager_email,
    CASE 
      WHEN status = 'ativo'
        THEN TRUE
      ELSE FALSE
    END AS is_active,
    CASE 
      WHEN pcd = 'sim'
        THEN TRUE
      ELSE FALSE
    END AS has_disabilty,
    ts_load
FROM datalake_gsheets_raw.talent_review