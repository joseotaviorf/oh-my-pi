SELECT
    sk_house_listing,
    banheira,
    box_de_vidro,
    varanda,
    fogao_e_galadeira_inclusos,
    piscina_privativa,
    churrasqueira_privativa,
    armarios_no_quarto,
    armarios_no_banheiro,
    armarios_na_cozinha,
    ar_condicionado,
    acesso_a_internet_incluso,
    chuveiro_a_gas,
    pode_ter_animais_de_estimacao,
    quarto_de_servico,
    banheiro_de_servico,
    garagem_fixa,
    varanda_gourmet,
    apartamento_cobertura,
    quarto_extra_reversivel,
    fogao,
    geladeira,
    sol_da_manha,
    sol_da_tarde,
    cortinas_corta_luz,
    cortinas_translucida,
    janela_anti_ruido,
    ventilador_de_teto,
    janelas_grandes,
    vista_livre,
    rua_silenciosa,
    chuveiro_eletrico,
    microondas,
    sofa,
    maquina_de_lavar,
    secadora,
    lava_e_seca,
    tanque,
    tela_nas_janelas,
    varal_de_roupas,
    tomadas_3_pinos,
    televisao,
    mesa_e_cadeiras,
    cafeteira,
    churrasqueira,
    acesso_sem_degraus,
    fogao_cooktop,
    utensilios_de_cozinha,
    cama_de_casal,
    cama_de_solteiro,
    espelho_no_banheiro,
    fechadura_eletronica,
    energia_no_imovel,
    condo_playground,
    condo_piscina,
    condo_churrasqueira,
    condo_quadra_esportiva,
    condo_academia,
    condo_salao_de_festas,
    condo_sauna,
    condo_lavanderia_no_predio,
    condo_gas_encanado,
    condo_portao_automatico,
    condo_espaco_gourmet_na_area_comum,
    condo_perto_de_metro_ou_trem,
    house_condition
FROM (
    SELECT
    --
    dhl.sk_house_listing,
    banheira.temcaracteristica                      AS banheira,
    box_de_vidro.temcaracteristica                  AS box_de_vidro,
    varanda.temcaracteristica                       AS varanda,
    fogao_e_galadeira_inclusos.temcaracteristica    AS fogao_e_galadeira_inclusos,
    piscina_privativa.temcaracteristica             AS piscina_privativa,
    churrasqueira_privativa.temcaracteristica       AS churrasqueira_privativa,
    armarios_no_quarto.temcaracteristica            AS armarios_no_quarto,
    armarios_no_banheiro.temcaracteristica          AS armarios_no_banheiro,
    armarios_na_cozinha.temcaracteristica           AS armarios_na_cozinha,
    ar_condicionado.temcaracteristica               AS ar_condicionado,
    acesso_a_internet_incluso.temcaracteristica     AS acesso_a_internet_incluso,
    chuveiro_a_gas.temcaracteristica                AS chuveiro_a_gas,
    pode_ter_animais_de_estimacao.temcaracteristica AS pode_ter_animais_de_estimacao,
    quarto_de_servico.temcaracteristica             AS quarto_de_servico,
    banheiro_de_servico.temcaracteristica           AS banheiro_de_servico,
    garagem_fixa.temcaracteristica                  AS garagem_fixa,
    varanda_gourmet.temcaracteristica               AS varanda_gourmet,
    apartamento_cobertura.temcaracteristica         AS apartamento_cobertura,
    quarto_extra_reversivel.temcaracteristica       AS quarto_extra_reversivel,
    fogao.temcaracteristica                         AS fogao,
    geladeira.temcaracteristica                     AS geladeira,
    sol_da_manha.temcaracteristica                  AS sol_da_manha,
    sol_da_tarde.temcaracteristica                  AS sol_da_tarde,
    cortinas_corta_luz.temcaracteristica            AS cortinas_corta_luz,
    cortinas_translucida.temcaracteristica          AS cortinas_translucida,
    janela_anti_ruido.temcaracteristica             AS janela_anti_ruido,
    ventilador_de_teto.temcaracteristica            AS ventilador_de_teto,
    janelas_grandes.temcaracteristica               AS janelas_grandes,
    vista_livre.temcaracteristica                   AS vista_livre,
    rua_silenciosa.temcaracteristica                AS rua_silenciosa,
    chuveiro_eletrico.temcaracteristica             AS chuveiro_eletrico,
    microondas.temcaracteristica                    AS microondas,
    sofa.temcaracteristica                          AS sofa,
    maquina_de_lavar.temcaracteristica              AS maquina_de_lavar,
    secadora.temcaracteristica                      AS secadora,
    lava_e_seca.temcaracteristica                   AS lava_e_seca,
    tanque.temcaracteristica                        AS tanque,
    tela_nas_janelas.temcaracteristica              AS tela_nas_janelas,
    varal_de_roupas.temcaracteristica               AS varal_de_roupas,
    tomadas_3_pinos.temcaracteristica               AS tomadas_3_pinos,
    televisao.temcaracteristica                     AS televisao,
    mesa_e_cadeiras.temcaracteristica               AS mesa_e_cadeiras,
    cafeteira.temcaracteristica                     AS cafeteira,
    churrasqueira.temcaracteristica                 AS churrasqueira,
    acesso_sem_degraus.temcaracteristica            AS acesso_sem_degraus,
    fogao_cooktop.temcaracteristica                 AS fogao_cooktop,
    utensilios_de_cozinha.temcaracteristica         AS utensilios_de_cozinha,
    cama_de_casal.temcaracteristica                 AS cama_de_casal,
    cama_de_solteiro.temcaracteristica              AS cama_de_solteiro,
    espelho_no_banheiro.temcaracteristica           AS espelho_no_banheiro,
    fechadura_eletronica.temcaracteristica          AS fechadura_eletronica,
    energia_no_imovel.temcaracteristica             AS energia_no_imovel,
    playground.temcaracteristica                    AS condo_playground,
    piscina.temcaracteristica                       AS condo_piscina,
    churrasqueira2.temcaracteristica                AS condo_churrasqueira,
    quadra_esportiva.temcaracteristica              AS condo_quadra_esportiva,
    academia.temcaracteristica                      AS condo_academia,
    salao_de_festas.temcaracteristica               AS condo_salao_de_festas,
    sauna.temcaracteristica                         AS condo_sauna,
    lavanderia_no_predio.temcaracteristica          AS condo_lavanderia_no_predio,
    gas_encanado.temcaracteristica                  AS condo_gas_encanado,
    portao_automatico.temcaracteristica             AS condo_portao_automatico,
    espaco_gourmet_na_area_comum.temcaracteristica  AS condo_espaco_gourmet_na_area_comum,
    perto_de_metro_ou_trem.temcaracteristica        AS condo_perto_de_metro_ou_trem,
    house_condition.maintenancecondition            AS house_condition,
    row_number() over 
        (partition by dhl.sk_house_listing
        order by
        banheira.atualizadoem desc,
        box_de_vidro.atualizadoem desc,
        varanda.atualizadoem desc,
        fogao_e_galadeira_inclusos.atualizadoem desc,
        piscina_privativa.atualizadoem desc,
        churrasqueira_privativa.atualizadoem desc,
        armarios_no_quarto.atualizadoem desc,
        armarios_no_banheiro.atualizadoem desc,
        armarios_na_cozinha.atualizadoem desc,
        ar_condicionado.atualizadoem desc,
        acesso_a_internet_incluso.atualizadoem desc,
        chuveiro_a_gas.atualizadoem desc,
        pode_ter_animais_de_estimacao.atualizadoem desc,
        quarto_de_servico.atualizadoem desc,
        banheiro_de_servico.atualizadoem desc,
        garagem_fixa.atualizadoem desc,
        varanda_gourmet.atualizadoem desc,
        apartamento_cobertura.atualizadoem desc,
        quarto_extra_reversivel.atualizadoem desc,
        fogao.atualizadoem desc,
        geladeira.atualizadoem desc,
        sol_da_manha.atualizadoem desc,
        sol_da_tarde.atualizadoem desc,
        cortinas_corta_luz.atualizadoem desc,
        cortinas_translucida.atualizadoem desc,
        janela_anti_ruido.atualizadoem desc,
        ventilador_de_teto.atualizadoem desc,
        janelas_grandes.atualizadoem desc,
        vista_livre.atualizadoem desc,
        rua_silenciosa.atualizadoem desc,
        chuveiro_eletrico.atualizadoem desc,
        microondas.atualizadoem desc,
        sofa.atualizadoem desc,
        maquina_de_lavar.atualizadoem desc,
        secadora.atualizadoem desc,
        lava_e_seca.atualizadoem desc,
        tanque.atualizadoem desc,
        tela_nas_janelas.atualizadoem desc,
        varal_de_roupas.atualizadoem desc,
        tomadas_3_pinos.atualizadoem desc,
        televisao.atualizadoem desc,
        mesa_e_cadeiras.atualizadoem desc,
        cafeteira.atualizadoem desc,
        churrasqueira.atualizadoem desc,
        acesso_sem_degraus.atualizadoem desc,
        fogao_cooktop.atualizadoem desc,
        utensilios_de_cozinha.atualizadoem desc,
        cama_de_casal.atualizadoem desc,
        cama_de_solteiro.atualizadoem desc,
        espelho_no_banheiro.atualizadoem desc,
        fechadura_eletronica.atualizadoem desc,
        energia_no_imovel.atualizadoem desc,
        playground.atualizadoem desc,
        piscina.atualizadoem desc,
        churrasqueira2.atualizadoem desc,
        quadra_esportiva.atualizadoem desc,
        academia.atualizadoem desc,
        salao_de_festas.atualizadoem desc,
        sauna.atualizadoem desc,
        lavanderia_no_predio.atualizadoem desc,
        gas_encanado.atualizadoem desc,
        portao_automatico.atualizadoem desc,
        espaco_gourmet_na_area_comum.atualizadoem desc,
        perto_de_metro_ou_trem.atualizadoem desc,
        house_condition.atualizadoem desc
        ) as rn
    --
    FROM dim_house_listing dhl
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo banheira
      ON dhl.id_house = banheira.imovel_id
     AND banheira.amenidades_id = 1 
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo box_de_vidro
      ON dhl.id_house = box_de_vidro.imovel_id
     AND box_de_vidro.amenidades_id = 2
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo varanda
      ON dhl.id_house = varanda.imovel_id
     AND varanda.amenidades_id = 3
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo fogao_e_galadeira_inclusos
      ON dhl.id_house = fogao_e_galadeira_inclusos.imovel_id
     AND fogao_e_galadeira_inclusos.amenidades_id = 4
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo piscina_privativa
      ON dhl.id_house = piscina_privativa.imovel_id
     AND piscina_privativa.amenidades_id = 5
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo churrasqueira_privativa
      ON dhl.id_house = churrasqueira_privativa.imovel_id
     AND churrasqueira_privativa.amenidades_id = 6
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo armarios_no_quarto
      ON dhl.id_house = armarios_no_quarto.imovel_id
     AND armarios_no_quarto.amenidades_id = 7
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo armarios_no_banheiro
      ON dhl.id_house = armarios_no_banheiro.imovel_id
     AND armarios_no_banheiro.amenidades_id = 8
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo armarios_na_cozinha
      ON dhl.id_house = armarios_na_cozinha.imovel_id
     AND armarios_na_cozinha.amenidades_id = 9
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo ar_condicionado
      ON dhl.id_house = ar_condicionado.imovel_id
     AND ar_condicionado.amenidades_id = 10
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo acesso_a_internet_incluso
      ON dhl.id_house = acesso_a_internet_incluso.imovel_id
     AND acesso_a_internet_incluso.amenidades_id = 11
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo chuveiro_a_gas
      ON dhl.id_house = chuveiro_a_gas.imovel_id
     AND chuveiro_a_gas.amenidades_id = 12
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo pode_ter_animais_de_estimacao
      ON dhl.id_house = pode_ter_animais_de_estimacao.imovel_id
     AND pode_ter_animais_de_estimacao.amenidades_id = 13
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo quarto_de_servico
      ON dhl.id_house = quarto_de_servico.imovel_id
     AND quarto_de_servico.amenidades_id = 14
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo banheiro_de_servico
      ON dhl.id_house = banheiro_de_servico.imovel_id
     AND banheiro_de_servico.amenidades_id = 15
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo garagem_fixa
      ON dhl.id_house = garagem_fixa.imovel_id
     AND garagem_fixa.amenidades_id = 16
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo varanda_gourmet
      ON dhl.id_house = varanda_gourmet.imovel_id
     AND varanda_gourmet.amenidades_id = 17
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo apartamento_cobertura
      ON dhl.id_house = apartamento_cobertura.imovel_id
     AND apartamento_cobertura.amenidades_id = 18
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo quarto_extra_reversivel
      ON dhl.id_house = quarto_extra_reversivel.imovel_id
     AND quarto_extra_reversivel.amenidades_id = 19
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo fogao
      ON dhl.id_house = fogao.imovel_id
     AND fogao.amenidades_id = 20
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo geladeira
      ON dhl.id_house = geladeira.imovel_id
     AND geladeira.amenidades_id = 21
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo sol_da_manha
      ON dhl.id_house = sol_da_manha.imovel_id
     AND sol_da_manha.amenidades_id = 22
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo sol_da_tarde
      ON dhl.id_house = sol_da_tarde.imovel_id
     AND sol_da_tarde.amenidades_id = 23
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo cortinas_corta_luz
      ON dhl.id_house = cortinas_corta_luz.imovel_id
     AND cortinas_corta_luz.amenidades_id = 24
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo cortinas_translucida
      ON dhl.id_house = cortinas_translucida.imovel_id
     AND cortinas_translucida.amenidades_id = 25
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo janela_anti_ruido
      ON dhl.id_house = janela_anti_ruido.imovel_id
     AND janela_anti_ruido.amenidades_id = 26
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo ventilador_de_teto
      ON dhl.id_house = ventilador_de_teto.imovel_id
     AND ventilador_de_teto.amenidades_id = 27
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo janelas_grandes
      ON dhl.id_house = janelas_grandes.imovel_id
     AND janelas_grandes.amenidades_id = 28
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo vista_livre
      ON dhl.id_house = vista_livre.imovel_id
     AND vista_livre.amenidades_id = 29
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo rua_silenciosa
      ON dhl.id_house = rua_silenciosa.imovel_id
     AND rua_silenciosa.amenidades_id = 30
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo chuveiro_eletrico
      ON dhl.id_house = chuveiro_eletrico.imovel_id
     AND chuveiro_eletrico.amenidades_id = 31
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo microondas
      ON dhl.id_house = microondas.imovel_id
     AND microondas.amenidades_id = 32
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo sofa
      ON dhl.id_house = sofa.imovel_id
     AND sofa.amenidades_id = 33
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo maquina_de_lavar
      ON dhl.id_house = maquina_de_lavar.imovel_id
     AND maquina_de_lavar.amenidades_id = 34
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo secadora
      ON dhl.id_house = secadora.imovel_id
     AND secadora.amenidades_id = 35
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo lava_e_seca
      ON dhl.id_house = lava_e_seca.imovel_id
     AND lava_e_seca.amenidades_id = 36
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo tanque
      ON dhl.id_house = tanque.imovel_id
     AND tanque.amenidades_id = 37
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo tela_nas_janelas
      ON dhl.id_house = tela_nas_janelas.imovel_id
     AND tela_nas_janelas.amenidades_id = 38
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo varal_de_roupas
      ON dhl.id_house = varal_de_roupas.imovel_id
     AND varal_de_roupas.amenidades_id = 39
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo tomadas_3_pinos
      ON dhl.id_house = tomadas_3_pinos.imovel_id
     AND tomadas_3_pinos.amenidades_id = 40
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo televisao
      ON dhl.id_house = televisao.imovel_id
     AND televisao.amenidades_id = 41
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo mesa_e_cadeiras
      ON dhl.id_house = mesa_e_cadeiras.imovel_id
     AND mesa_e_cadeiras.amenidades_id = 42
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo cafeteira
      ON dhl.id_house = cafeteira.imovel_id
     AND cafeteira.amenidades_id = 43
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo churrasqueira
      ON dhl.id_house = churrasqueira.imovel_id
     AND churrasqueira.amenidades_id = 44
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo acesso_sem_degraus
      ON dhl.id_house = acesso_sem_degraus.imovel_id
     AND acesso_sem_degraus.amenidades_id = 45
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo fogao_cooktop
      ON dhl.id_house = fogao_cooktop.imovel_id
     AND fogao_cooktop.amenidades_id = 46
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo utensilios_de_cozinha
      ON dhl.id_house = utensilios_de_cozinha.imovel_id
     AND utensilios_de_cozinha.amenidades_id = 47
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo cama_de_casal
      ON dhl.id_house = cama_de_casal.imovel_id
     AND cama_de_casal.amenidades_id = 48
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo cama_de_solteiro
      ON dhl.id_house = cama_de_solteiro.imovel_id
     AND cama_de_solteiro.amenidades_id = 49
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo espelho_no_banheiro
      ON dhl.id_house = espelho_no_banheiro.imovel_id
     AND espelho_no_banheiro.amenidades_id = 50
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo fechadura_eletronica
      ON dhl.id_house = fechadura_eletronica.imovel_id
     AND fechadura_eletronica.amenidades_id = 51
    --
    LEFT JOIN datalake_raw.ebdb_amenidadesinfo energia_no_imovel
      ON dhl.id_house = energia_no_imovel.imovel_id
     AND energia_no_imovel.amenidades_id = 52
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo playground
      ON dhl.id_house = playground.imovel_id
     AND playground.instalacao_id = 1
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo piscina
      ON dhl.id_house = piscina.imovel_id
     AND piscina.instalacao_id = 2
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo churrasqueira2
      ON dhl.id_house = churrasqueira2.imovel_id
     AND churrasqueira2.instalacao_id = 3
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo quadra_esportiva
      ON dhl.id_house = quadra_esportiva.imovel_id
     AND quadra_esportiva.instalacao_id = 4
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo academia
      ON dhl.id_house = academia.imovel_id
     AND academia.instalacao_id = 5
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo salao_de_festas
      ON dhl.id_house = salao_de_festas.imovel_id
     AND salao_de_festas.instalacao_id = 6
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo sauna
      ON dhl.id_house = sauna.imovel_id
     AND sauna.instalacao_id = 7
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo lavanderia_no_predio
      ON dhl.id_house = lavanderia_no_predio.imovel_id
     AND lavanderia_no_predio.instalacao_id = 8
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo gas_encanado
      ON dhl.id_house = gas_encanado.imovel_id
     AND gas_encanado.instalacao_id = 9
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo portao_automatico
      ON dhl.id_house = portao_automatico.imovel_id
     AND portao_automatico.instalacao_id = 10
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo espaco_gourmet_na_area_comum
      ON dhl.id_house = espaco_gourmet_na_area_comum.imovel_id
     AND espaco_gourmet_na_area_comum.instalacao_id = 11
    --
    LEFT JOIN datalake_raw.ebdb_instalacaoinfo perto_de_metro_ou_trem
      ON dhl.id_house = perto_de_metro_ou_trem.imovel_id
     AND perto_de_metro_ou_trem.instalacao_id = 12
    --
    LEFT JOIN datalake_raw.ebdb_housemaintenancecondition house_condition
      ON dhl.id_house = house_condition.houseid
    ) base
WHERE base.rn = 1
ORDER BY 1
;