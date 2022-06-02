WITH backtest AS (
  SELECT
    id_proposal,
    id_proponent,
    REPLACE(REPLACE(cpf,".",""),"-","") AS cpf,
    renda_presumida AS transunion_presumed_income,
    class_banc_ult_decl AS transunion_irpf_last_decl_class,
    ind_estab_emprego AS transunion_index_job_stability,
    indic_seg_12 AS transunion_index_seg_12,
    indic_seg_12_cob AS transunion_index_seg_12_charge,
    indic_seg_12_ecom AS transunion_index_seg_12_ecom,
    indic_seg_12_fin AS transunion_index_seg_12_fin,
    indic_seg_12_tele AS transunion_index_seg_12_tele,
    indic_seg_24 AS transunion_index_seg_24,
    indic_seg_24_cob AS transunion_index_seg_24_charge,
    indic_seg_24_ecom AS transunion_index_seg_24_ecom,
    indic_seg_24_fin AS transunion_index_seg_24_fin,
    indic_seg_24_tele AS transunion_index_seg_24_tele,
    indic_seg_6 AS transunion_index_seg_6,
    indic_seg_6_cob AS transunion_index_seg_6_cob,
    indic_seg_6_ecom AS transunion_index_seg_6_ecom,
    indic_seg_6_fin AS transunion_index_seg_6_fin,
    indic_seg_6_tele AS transunion_index_seg_6_tele,
    porte_empregador AS transunion_employer_size,
    sc_situacao AS transunion_sc_situation,
    automoveis_percap_m_munic AS transunion_percap_m_munic_cars,
    caminhao_percap_m_munic AS transunion_percap_m_munic_trucks,
    caminonete_percap_m_munic AS transunion_percap_m_munic_pickups,
    utilitario_percap_m_munic AS transunion_percap_m_munic_utilitario,
    veic_outros_percap_m_munic AS transunion_percap_m_munic_others,
    dist_centro_m AS transunion_dist_cep_to_city_center,
    dist_fronteira_m AS transunion_dist_cep_to_nearest_border,
    dist_risco_m AS transunion_dist_cep_to_nearest_subnormal_aglomerate,
    idade_media AS transunion_avg_cep_residents_age,
    idhm AS transunion_idhm,
    leito_priv_percap_mm_munic AS transunion_percap_mm_munic_private_hosp_beds,
    leito_pub_percap_mm_munic AS transunion_percap_mm_munic_public_hosp_beds,
    leito_sus_percap_mm_munic AS transunion_percap_mm_munic_sus_hosp_beds,
    max_decl_10_hh AS transunion_max_household_irpf_decl_10_years,
    max_decl_3_hh AS transunion_max_household_irpf_decl_3_years,
    max_decl_6_hh AS transunion_max_household_irpf_decl_6_years,
    max_idade_hh AS transunion_max_household_age,
    max_ind_estab_emprego_hh AS transunion_max_household_index_job_stability,
    max_porte_empregador_hh AS transunion_max_household_employer_size,
    max_porte_qsa_hh AS transunion_max_household_qsa_size,
    max_renda_pres_hh AS transunion_max_household_presumed_income,
    media_idade_hh AS transunion_avg_household_age,
    media_renda_pres_hh AS transunion_avg_household_presumed_income,
    media_renda_presumida AS transunion_avg_cep_residents_presumed_income,
    min_idade_hh AS transunion_min_household_age,
    min_renda_pres_hh AS transunion_min_household_presumed_income,
    moto_percap_m_munic AS transunion_percap_m_munic_motorcycles,
    percent_00_17 AS transunion_percent_cep_residents_00_17_years,
    percent_18_29 AS transunion_percent_cep_residents_18_29_years,
    percent_30_39 AS transunion_percent_cep_residents_30_39_years,
    percent_40_49 AS transunion_percent_cep_residents_40_49_years,
    percent_50_59 AS transunion_percent_cep_residents_50_59_years,
    percent_60_69 AS transunion_percent_cep_residents_60_69_years,
    percent_70_mais AS transunion_percent_cep_residents_gt_70_years,
    percent_bolsa_familia AS transunion_percent_cep_residents_bolsa_familia,
    percent_decl_10_00 AS transunion_percent_cep_residents_irpf_decl_10_00,
    percent_decl_10_01 AS transunion_percent_cep_residents_irpf_decl_10_01,
    percent_decl_10_02_04 AS transunion_percent_cep_residents_irpf_decl_10_02_04,
    percent_decl_10_05_09 AS transunion_percent_cep_residents_irpf_decl_10_05_09,
    percent_decl_10_10 AS transunion_percent_cep_residents_irpf_decl_10_10,
    percent_decl_pagar_10_00 AS transunion_percent_cep_residents_irpf_decl_pend_10_00,
    percent_decl_pagar_10_01 AS transunion_percent_cep_residents_irpf_decl_pend_10_01,
    percent_decl_pagar_10_02_04 AS transunion_percent_cep_residents_irpf_decl_pend_10_02_04,
    percent_decl_pagar_10_05_09 AS transunion_percent_cep_residents_irpf_decl_pend_10_05_09,
    percent_decl_pagar_10_10 AS transunion_percent_cep_residents_irpf_decl_pend_10_10,
    percent_decl_rest_10_00 AS transunion_percent_cep_residents_irpf_decl_rest_10_00,
    percent_decl_rest_10_01 AS transunion_percent_cep_residents_irpf_decl_rest_10_01,
    percent_decl_rest_10_02_04 AS transunion_percent_cep_residents_irpf_decl_rest_10_02_04,
    percent_decl_rest_10_05_09 AS transunion_percent_cep_residents_irpf_decl_rest_10_05_09,
    percent_decl_rest_10_10 AS transunion_percent_cep_residents_irpf_decl_rest_10_10,
    percent_escol_00 AS transunion_percent_cep_residents_escol_00,
    percent_escol_01 AS transunion_percent_cep_residents_escol_01,
    percent_escol_02 AS transunion_percent_cep_residents_escol_02,
    percent_escol_03 AS transunion_percent_cep_residents_escol_03,
    percent_escol_04 AS transunion_percent_cep_residents_escol_04,
    percent_escol_05 AS transunion_percent_cep_residents_escol_05,
    percent_escol_06 AS transunion_percent_cep_residents_escol_06,
    percent_escol_07 AS transunion_percent_cep_residents_escol_07,
    percent_escol_08 AS transunion_percent_cep_residents_escol_08,
    percent_escol_09 AS transunion_percent_cep_residents_escol_09,
    percent_escol_10 AS transunion_percent_cep_residents_escol_10,
    percent_func_pub AS transunion_percent_cep_residents_public_employee,
    percent_indic_00 AS transunion_percent_cep_residents_registration_rules_00,
    percent_indic_01 AS transunion_percent_cep_residents_registration_rules_01,
    percent_indic_02 AS transunion_percent_cep_residents_registration_rules_02,
    percent_indic_03 AS transunion_percent_cep_residents_registration_rules_03,
    percent_indic_04 AS transunion_percent_cep_residents_registration_rules_04,
    percent_pop_urbana_munic AS transunion_percent_urban_population_munic,
    percent_renda_01 AS transunion_percent_cep_residents_presumed_income_01,
    percent_renda_02 AS transunion_percent_cep_residents_presumed_income_02,
    percent_renda_03 AS transunion_percent_cep_residents_presumed_income_03,
    percent_renda_04 AS transunion_percent_cep_residents_presumed_income_04,
    percent_renda_05 AS transunion_percent_cep_residents_presumed_income_05,
    percent_renda_06 AS transunion_percent_cep_residents_presumed_income_06,
    percent_renda_07 AS transunion_percent_cep_residents_presumed_income_07,
    percent_segmento_alto AS transunion_percent_cep_residents_seg_high,
    percent_segmento_baixo AS transunion_percent_cep_residents_seg_low,
    percent_segmento_medio AS transunion_percent_cep_residents_seg_mid,
    percent_segmento_cob_alto AS transunion_percent_cep_residents_seg_charge_high,
    percent_segmento_cob_baixo AS transunion_percent_cep_residents_seg_charge_low,
    percent_segmento_cob_medio AS transunion_percent_cep_residents_seg_charge_mid,
    percent_segmento_ecom_alto AS transunion_percent_cep_residents_seg_ecom_high,
    percent_segmento_ecom_baixo AS transunion_percent_cep_residents_seg_ecom_low,
    percent_segmento_ecom_medio AS transunion_percent_cep_residents_seg_ecom_mid,
    percent_segmento_fin_alto AS transunion_percent_cep_residents_seg_fin_high,
    percent_segmento_fin_baixo AS transunion_percent_cep_residents_seg_fin_low,
    percent_segmento_fin_medio AS transunion_percent_cep_residents_seg_fin_mid,
    percent_segmento_muito_alto AS transunion_percent_cep_residents_seg_very_high,
    percent_segmento_muito_baixo AS transunion_percent_cep_residents_seg_very_low,
    percent_segmento_tele_alto AS transunion_percent_cep_residents_seg_tele_high,
    percent_segmento_tele_baixo AS transunion_percent_cep_residents_seg_tele_low,
    percent_segmento_tele_medio AS transunion_percent_cep_residents_seg_tele_mid,
    percent_segmento_tele_muito_alto AS transunion_percent_cep_residents_seg_tele_very_high,
    percent_segmento_tele_muito_baixo AS transunion_percent_cep_residents_seg_tele_very_low,
    percent_sexo_f AS transunion_percent_cep_residents_female,
    percent_sexo_m AS transunion_percent_cep_residents_male,
    pib_perc_munic AS transunion_percap_pib_munic,
    pib_percent_agro_munic AS transunion_percent_pib_agro_munic,
    pib_percent_ind_munic AS transunion_percent_pib_ind_munic,
    pib_percent_serv_munic AS transunion_percent_pib_serv_munic,
    qtd_decl_10 AS transunion_qtd_irpf_decl_10_years,
    qtd_decl_3 AS transunion_qtd_irpf_decl_3_years,
    qtd_decl_6 AS transunion_qtd_irpf_decl_6_years,
    qtd_decl_isento AS transunion_qtd_irpf_decl_isento,
    qtd_decl_pagar_10 AS transunion_qtd_irpf_decl_pend_10_years,
    qtd_decl_pagar_3 AS transunion_qtd_irpf_decl_pend_3_years,
    qtd_decl_pagar_6 AS transunion_qtd_irpf_decl_pend_6_years,
    qtd_decl_rest_10 AS transunion_qtd_irpf_decl_rest_10_years,
    qtd_decl_rest_3 AS transunion_qtd_irpf_decl_rest_3_years,
    qtd_decl_rest_6 AS transunion_qtd_irpf_decl_rest_6_years,
    qtd_email AS transunion_qtd_doc_distinct_emails,
    qtd_endereco AS transunion_qtd_doc_distinct_addresses,
    qtd_ind_estab_emprego_hh AS transunion_qtd_household_index_job_stability,
    qtd_pessoas_hh AS transunion_qtd_household_persons,
    qtd_tel_cel AS transunion_qtd_doc_distinct_tel_cel,
    qtd_tel_fixo AS transunion_qtd_doc_distinct_tel_fixo,
    sc_idade_media AS transunion_avg_sc_age,
    sc_media_morador AS transunion_avg_sc_resident,
    sc_media_renda_presumida AS transunion_avg_sc_presumed_income,
    sc_percent_00_17 AS transunion_percent_sc_00_17_years,
    sc_percent_18_29 AS transunion_percent_sc_18_29_years,
    sc_percent_30_39 AS transunion_percent_sc_30_39_years,
    sc_percent_40_49 AS transunion_percent_sc_40_49_years,
    sc_percent_50_59 AS transunion_percent_sc_50_59_years,
    sc_percent_60_69 AS transunion_percent_sc_60_69_years,
    sc_percent_70_95 AS transunion_percent_sc_70_95_years,
    sc_percent_bolsa_familia AS transunion_percent_sc_bolsa_familia,
    sc_percent_consultas_12_00 AS transunion_percent_sc_consultas_12_00,
    sc_percent_consultas_12_01 AS transunion_percent_sc_consultas_12_01,
    sc_percent_consultas_12_02 AS transunion_percent_sc_consultas_12_02,
    sc_percent_consultas_12_03 AS transunion_percent_sc_consultas_12_03,
    sc_percent_consultas_12_04 AS transunion_percent_sc_consultas_12_04,
    sc_percent_consultas_12_cob_00 AS transunion_percent_sc_consultas_12_charge_00,
    sc_percent_consultas_12_cob_01 AS transunion_percent_sc_consultas_12_charge_01,
    sc_percent_consultas_12_cob_02 AS transunion_percent_sc_consultas_12_charge_02,
    sc_percent_consultas_12_ecom_00 AS transunion_percent_sc_consultas_12_ecom_00,
    sc_percent_consultas_12_ecom_01 AS transunion_percent_sc_consultas_12_ecom_01,
    sc_percent_consultas_12_ecom_02 AS transunion_percent_sc_consultas_12_ecom_02,
    sc_percent_consultas_12_fin_00 AS transunion_percent_sc_consultas_12_fin_00,
    sc_percent_consultas_12_fin_01 AS transunion_percent_sc_consultas_12_fin_01,
    sc_percent_consultas_12_fin_02 AS transunion_percent_sc_consultas_12_fin_02,
    sc_percent_consultas_12_tele_00 AS transunion_percent_sc_consultas_12_tele_00,
    sc_percent_consultas_12_tele_01 AS transunion_percent_sc_consultas_12_tele_01,
    sc_percent_consultas_12_tele_02 AS transunion_percent_sc_consultas_12_tele_02,
    sc_percent_consultas_12_tele_03 AS transunion_percent_sc_consultas_12_tele_03,
    sc_percent_consultas_12_tele_04 AS transunion_percent_sc_consultas_12_tele_04,
    sc_percent_decl_10_00 AS transunion_percent_sc_irpf_decl_10_00,
    sc_percent_decl_10_01 AS transunion_percent_sc_irpf_decl_10_01,
    sc_percent_decl_10_02 AS transunion_percent_sc_irpf_decl_10_02,
    sc_percent_decl_10_03 AS transunion_percent_sc_irpf_decl_10_03,
    sc_percent_decl_10_04 AS transunion_percent_sc_irpf_decl_10_04,
    sc_percent_decl_pagar_10_00 AS transunion_percent_sc_irpf_decl_pend_10_00,
    sc_percent_decl_pagar_10_01 AS transunion_percent_sc_irpf_decl_pend_10_01,
    sc_percent_decl_pagar_10_02 AS transunion_percent_sc_irpf_decl_pend_10_02,
    sc_percent_decl_pagar_10_03 AS transunion_percent_sc_irpf_decl_pend_10_03,
    sc_percent_decl_pagar_10_04 AS transunion_percent_sc_irpf_decl_pend_10_04,
    sc_percent_decl_rest_10_00 AS transunion_percent_sc_irpf_decl_rest_10_00,
    sc_percent_decl_rest_10_01 AS transunion_percent_sc_irpf_decl_rest_10_01,
    sc_percent_decl_rest_10_02 AS transunion_percent_sc_irpf_decl_rest_10_02,
    sc_percent_decl_rest_10_03 AS transunion_percent_sc_irpf_decl_rest_10_03,
    sc_percent_decl_rest_10_04 AS transunion_percent_sc_irpf_decl_rest_10_04,
    sc_percent_domici_1_banheiro AS transunion_percent_sc_residence_1_bathroom,
    sc_percent_domici_1_morador AS transunion_percent_sc_residence_1_resident,
    sc_percent_domici_2_banheiros AS transunion_percent_sc_residence_2_bathrooms,
    sc_percent_domici_2_morador AS transunion_percent_sc_residence_2_residents,
    sc_percent_domici_3_morador AS transunion_percent_sc_residence_3_residents,
    sc_percent_domici_4_morador AS transunion_percent_sc_residence_4_residents,
    sc_percent_domici_adquiridos_outras_formas AS transunion_percent_sc_residence_other_ways,
    sc_percent_domici_agua_rede_geral AS transunion_percent_sc_residence_water_supply,
    sc_percent_domici_alugados AS transunion_percent_sc_residence_rent,
    sc_percent_domici_apartamento AS transunion_percent_sc_residence_apartments,
    sc_percent_domici_banheiro_uso_exclusivo AS transunion_percent_sc_residence_exclusive_bathroom,
    sc_percent_domici_casa AS transunion_percent_sc_residence_houses,
    sc_percent_domici_casa_em_condominio_vila AS transunion_percent_sc_residence_condo_houses,
    sc_percent_domici_coleta_lixo AS transunion_percent_sc_residence_garbage_collection,
    sc_percent_domici_coletado_cacamba AS transunion_percent_sc_residence_garbage_collection_cacamba,
    sc_percent_domici_coletado_outras_formas AS transunion_percent_sc_residence_garbage_collection_other_ways,
    sc_percent_domici_coletado_servico_limpeza AS transunion_percent_sc_residence_garbage_collection_cleanup_service,
    sc_percent_domici_com_esgoto_ceu_aberto AS transunion_percent_sc_residence_open_sewer,
    sc_percent_domici_com_lixo_acumulado AS transunion_percent_sc_residence_accumulated_garbage,
    sc_percent_domici_em_aquisicao AS transunion_percent_sc_residence_in_acquiring,
    sc_percent_domici_energia_eletrica AS transunion_percent_sc_residence_electrical_supply,
    sc_percent_domici_energia_eletrica_medidor_compartil AS transunion_percent_sc_residence_energy_meter_shared,
    sc_percent_domici_energia_eletrica_medidor_exclusivo AS transunion_percent_sc_residence_energy_meter_exclusive,
    sc_percent_domici_energia_eletrica_outras_formas AS transunion_percent_sc_residence_energy_meter_other_ways,
    sc_percent_domici_energia_eletrica_rede_distribuicao AS transunion_percent_sc_residence_power_distribution_network,
    sc_percent_domici_energia_eletrica_sem_medidor AS transunion_percent_sc_residence_energy_meter_without,
    sc_percent_domici_esgoto_demais AS transunion_percent_sc_residence_sewage_too_much,
    sc_percent_domici_esgoto_fossa_septica AS transunion_percent_sc_residence_sewage_septic_tank,
    sc_percent_domici_esgoto_rede_publica AS transunion_percent_sc_residence_sewage_public_network,
    sc_percent_domici_mais_2_banheiros AS transunion_percent_sc_residence_gt_2_bathrooms,
    sc_percent_domici_mais_4_morador AS transunion_percent_sc_residence_gt_4_residents,
    sc_percent_domici_moradia_adequada AS transunion_percent_sc_residence_adequate_housing,
    sc_percent_domici_moradia_inadequada AS transunion_percent_sc_residence_inadequate_housing,
    sc_percent_domici_moradia_semi_adequada AS transunion_percent_sc_residence_semi_adequate_housing,
    sc_percent_domici_permanentes AS transunion_percent_sc_residence_permanent_residents,
    sc_percent_domici_quitados AS transunion_percent_sc_residence_paid_off,
    sc_percent_domici_rendimento_mensal_acima_10_sm AS transunion_percent_sc_residence_monthly_income_gt_10sm,
    sc_percent_domici_rendimento_mensal_ate_1s8_sm AS transunion_percent_sc_residence_monthly_income_until_1s8_sm,
    sc_percent_domici_rendimento_mensal_de_1_a_2_sm AS transunion_percent_sc_residence_monthly_income_1_a_2_sm,
    sc_percent_domici_rendimento_mensal_de_1s2_a_1_sm AS transunion_percent_sc_residence_monthly_income_1s2_a_1_sm,
    sc_percent_domici_rendimento_mensal_de_1s4_a_1s2_sm AS transunion_percent_sc_residence_monthly_income_1s4_a_1s2_sm,
    sc_percent_domici_rendimento_mensal_de_1s8_a_1s4_sm AS transunion_percent_sc_residence_monthly_income_1s8_a_1s4_sm,
    sc_percent_domici_rendimento_mensal_de_2_a_3_sm AS transunion_percent_sc_residence_monthly_income_2_a_3_sm,
    sc_percent_domici_rendimento_mensal_de_3_a_5_sm AS transunion_percent_sc_residence_monthly_income_3_a_5_sm,
    sc_percent_domici_rendimento_mensal_de_5_a_10_sm AS transunion_percent_sc_residence_monthly_income_5_a_10_sm,
    sc_percent_domici_sem_arborizacao AS transunion_percent_sc_residence_afforestation_without,
    sc_percent_domici_sem_bueiro AS transunion_percent_sc_residence_manhole_without,
    sc_percent_domici_sem_calcada AS transunion_percent_sc_residence_sidewalk_without,
    sc_percent_domici_sem_guia AS transunion_percent_sc_residence_curb_without,
    sc_percent_domici_sem_identificacao_logradouro AS transunion_percent_sc_residence_public_place_without,
    sc_percent_domici_sem_iluminacao_publica AS transunion_percent_sc_residence_public_energy_without,
    sc_percent_domici_sem_morador_feminino AS transunion_percent_sc_residence_female_resident_without,
    sc_percent_domici_sem_morador_masculino AS transunion_percent_sc_residence_male_resident_without,
    sc_percent_domici_sem_pavimentacao AS transunion_percent_sc_residence_paving_without,
    sc_percent_domici_sem_rampa_acessibilidade AS transunion_percent_sc_residence_accessibility_ramp_without,
    sc_percent_domici_sem_rendimento_mensal AS transunion_percent_sc_residence_monthly_income_without,
    sc_percent_escol_00 AS transunion_percent_sc_escol_00,
    sc_percent_escol_01 AS transunion_percent_sc_escol_01,
    sc_percent_escol_02 AS transunion_percent_sc_escol_02,
    sc_percent_escol_03 AS transunion_percent_sc_escol_03,
    sc_percent_escol_04 AS transunion_percent_sc_escol_04,
    sc_percent_escol_05 AS transunion_percent_sc_escol_05,
    sc_percent_escol_06 AS transunion_percent_sc_escol_06,
    sc_percent_escol_07 AS transunion_percent_sc_escol_07,
    sc_percent_escol_08 AS transunion_percent_sc_escol_08,
    sc_percent_escol_09 AS transunion_percent_sc_escol_09,
    sc_percent_escol_10 AS transunion_percent_sc_escol_10,
    sc_percent_func_pub AS transunion_percent_sc_public_employee,
    sc_percent_morador_agua_rede_geral AS transunion_percent_sc_resident_water_supply,
    sc_percent_morador_apartamento AS transunion_percent_sc_resident_apartment,
    sc_percent_morador_casa AS transunion_percent_sc_resident_house,
    sc_percent_morador_casa_condominio_vila AS transunion_percent_sc_resident_condo_house,
    sc_percent_morador_coleta_lixo AS transunion_percent_sc_resident_garbage_collection,
    sc_percent_morador_coleta_lixo_servico AS transunion_percent_sc_resident_gargabe_collection_service,
    sc_percent_morador_domici_adquiridos_outras_formas AS transunion_percent_sc_resident_residence_acquired_other_ways,
    sc_percent_morador_domici_alugado AS transunion_percent_sc_resident_residence_rent,
    sc_percent_morador_domici_em_aquisicao AS transunion_percent_sc_resident_residence_in_acquisition,
    sc_percent_morador_domici_permanente AS transunion_percent_sc_resident_residence_permanent,
    sc_percent_morador_domici_quitado AS transunion_percent_sc_resident_residence_paid_off,
    sc_percent_morador_energia_eletrica AS transunion_percent_sc_resident_residence_electrical_supply,
    sc_percent_pessoas_0_4_anos AS transunion_percent_people_0_4_years,
    sc_percent_pessoas_10_14_anos AS transunion_percent_people_10_14_years,
    sc_percent_pessoas_15_17_anos AS transunion_percent_people_15_17_years,
    sc_percent_pessoas_18_19_anos AS transunion_percent_people_18_19_years,
    sc_percent_pessoas_20_24_anos AS transunion_percent_people_20_24_years,
    sc_percent_pessoas_25_29_anos AS transunion_percent_people_25_29_years,
    sc_percent_pessoas_30_34_anos AS transunion_percent_people_30_34_years,
    sc_percent_pessoas_35_39_anos AS transunion_percent_people_35_39_years,
    sc_percent_pessoas_40_44_anos AS transunion_percent_people_40_44_years,
    sc_percent_pessoas_45_49_anos AS transunion_percent_people_45_49_years,
    sc_percent_pessoas_50_54_anos AS transunion_percent_people_50_54_years,
    sc_percent_pessoas_55_59_anos AS transunion_percent_people_55_59_years,
    sc_percent_pessoas_5_9_anos AS transunion_percent_people_5_9_years,
    sc_percent_pessoas_60_69_anos AS transunion_percent_people_60_69_years,
    sc_percent_pessoas_com_registro_nascimento AS transunion_percent_people_registration_birth,
    sc_percent_pessoas_mais_69_anos AS transunion_percent_people_gt_69_years,
    sc_percent_pessoas_nao_sabem_registro_nascimento AS transunion_percent_people_registration_birth_not_known,
    sc_percent_pessoas_rendimento_mensal_10_a_15_sm AS transunion_percent_people_monthly_income_10_a_15_sm,
    sc_percent_pessoas_rendimento_mensal_15_a_20_sm AS transunion_percent_people_monthly_income_15_a_20_sm,
    sc_percent_pessoas_rendimento_mensal_1_a_2_sm AS transunion_percent_people_monthly_income_1_a_2_sm,
    sc_percent_pessoas_rendimento_mensal_1s2_a_1_sm AS transunion_percent_people_monthly_income_1s2_a_1_sm,
    sc_percent_pessoas_rendimento_mensal_2_a_3_sm AS transunion_percent_people_monthly_income_2_a_3_sm,
    sc_percent_pessoas_rendimento_mensal_3_a_5_sm AS transunion_percent_people_monthly_income_3_a_5_sm,
    sc_percent_pessoas_rendimento_mensal_5_a_10_sm AS transunion_percent_people_monthly_income_5_a_10_sm,
    sc_percent_pessoas_rendimento_mensal_acima_20_sm AS transunion_percent_people_monthly_income_gt_20_sm,
    sc_percent_pessoas_rendimento_mensal_ate_1s2_sm AS transunion_percent_people_monthly_income_until_1s2_sm,
    sc_percent_pessoas_sem_registro_nascimento AS transunion_percent_people_registration_birth_without,
    sc_percent_pessoas_sem_rendimento_mensal AS transunion_percent_people_monthly_income_without,
    sc_percent_renda_01 AS transunion_percent_sc_income_01,
    sc_percent_renda_02 AS transunion_percent_sc_income_02,
    sc_percent_renda_03 AS transunion_percent_sc_income_03,
    sc_percent_renda_04 AS transunion_percent_sc_income_04,
    sc_percent_renda_05 AS transunion_percent_sc_income_05,
    sc_percent_renda_06 AS transunion_percent_sc_income_06,
    sc_percent_renda_07 AS transunion_percent_sc_income_07,
    sc_percent_responsa_domici_alfabetizado_feminino AS transunion_percent_sc_responsible_person_literate_female,
    sc_percent_responsa_domici_alfabetizado_masculino AS transunion_percent_sc_responsible_person_literate_male,
    sc_percent_responsa_domici_sexo_feminino AS transunion_percent_sc_responsible_person_female,
    sc_percent_responsa_domici_sexo_masculino AS transunion_percent_sc_responsible_person_male,
    sc_percent_responsa_rendimento_mensal_10_a_15_sm AS transunion_percent_sc_responsible_person_monthly_income_10_a_15_sm,
    sc_percent_responsa_rendimento_mensal_15_a_20_sm AS transunion_percent_sc_responsible_person_monthly_income_15_a_20_sm,
    sc_percent_responsa_rendimento_mensal_1_a_2_sm AS transunion_percent_sc_responsible_person_monthly_income_1_a_2_sm,
    sc_percent_responsa_rendimento_mensal_1s2_a_1_sm AS transunion_percent_sc_responsible_person_monthly_income_1s2_a_1_sm,
    sc_percent_responsa_rendimento_mensal_2_a_3_sm AS transunion_percent_sc_responsible_person_monthly_income_2_a_3_sm,
    sc_percent_responsa_rendimento_mensal_3_a_5_sm AS transunion_percent_sc_responsible_person_monthly_income_3_a_5_sm,
    sc_percent_responsa_rendimento_mensal_5_a_10_sm AS transunion_percent_sc_responsible_person_monthly_income_5_a_10_sm,
    sc_percent_responsa_rendimento_mensal_acima_20_sm AS transunion_percent_sc_responsible_person_monthly_income_gt_20_sm,
    sc_percent_responsa_rendimento_mensal_ate_1s2_sm AS transunion_percent_sc_responsible_person_monthly_income_until_1s2_sm,
    sc_percent_responsa_sem_rendimento_mensal AS transunion_percent_sc_responsible_person_monthly_income_without,
    sc_percent_sexo_f AS transunion_percent_sc_female,
    sc_percent_sexo_m AS transunion_percent_sc_male,
    sc_percentual_qsa AS transunion_percent_sc_qsa,
    sc_rendimento_medio_mensal_domici_salario_minimo AS transunion_percent_sc_residence_avg_monthly_income_salario_minimo,
    sc_rendimento_medio_mensal_respons_domici_salario_minimo AS transunion_percent_sc_responsible_person_avg_monthly_income_salario_minimo,
    sc_valor_rendimento_mensal_pessoas_sm AS transunion_sum_sc_persons_monthly_income_gt_10_years,
    sc_valor_rendimento_mensal_responsa_sm AS transunion_sum_sc_responsible_persons_monthly_income,
    sum_renda_pres_hh AS transunion_sum_household_presumed_income,
    tempo_emissao_cpf AS transunion_time_cpf_emission,
    tmp_meses_ult_tel_cel AS transunion_time_months_last_cel_phone,
    tmp_meses_ult_tel_fixo AS transunion_time_months_last_tel_fixo,
    tmp_ult_decl_a_restit AS transunion_time_last_irpf_decl_rest,
    tmpo_ult_decl AS transunion_time_last_irpf_decl,
    tmpo_ult_decl_a_pagar AS transunion_time_last_irpf_decl_pend,
    flag_11_15_anos_hh AS transunion_has_household_11_15_years,
    flag_16_17_anos_hh AS transunion_has_household_16_17_years,
    flag_18_20_anos_hh AS transunion_has_household_18_20_years,
    flag_21_25_anos_hh AS transunion_has_household_21_25_years,
    flag_25_30_anos_hh AS transunion_has_household_25_30_years,
    flag_3_5_anos_hh AS transunion_has_household_3_5_years,
    flag_6_10_anos_hh AS transunion_has_household_6_10_years,
    flag_ate_2_anos_hh AS transunion_has_household_until_2_years,
    flag_func_pub AS transunion_is_public_employee,
    flag_socio AS transunion_is_business_partner,
    flag_tel_cel_procon AS transunion_is_tel_cel_procon,
    flag_tel_fixo_assin AS transunion_is_tel_fixo_assin,
    flag_tel_fixo_procon AS transunion_is_tel_fixo_procon,
    flg_bolsa_familia_hh AS transunion_has_household_bolsa_familia,
    flg_decl_10_hh AS transunion_has_household_irpf_decl_10_years,
    flg_decl_3_hh AS transunion_has_household_irpf_decl_3_years,
    flg_decl_6_hh AS transunion_has_household_irpf_decl_6_years,
    flg_decl_pagar_10_hh AS transunion_has_household_irpf_decl_pend_10_years,
    flg_decl_pagar_3_hh AS transunion_has_household_irpf_decl_pend_3_years,
    flg_decl_pagar_6_hh AS transunion_has_household_irpf_decl_pend_6_years,
    flg_decl_rest_10a_hh AS transunion_has_household_irpf_decl_rest_10_years,
    flg_decl_rest_3a_hh AS transunion_has_household_irpf_decl_rest_3_years,
    flg_decl_rest_6a_hh AS transunion_has_household_irpf_decl_rest_6_years,
    flg_func_pub_hh AS transunion_has_household_public_employee,
    flg_idade_35_hh AS transunion_has_household_gt_35_years,
    flg_ind_estab_emprego_hh AS transunion_has_household_index_job_stability,
    flg_indicador_hh AS transunion_has_household_invalid_registration_rules,
    flg_indice_cob_1_hh AS transunion_has_household_index_charge_1,
    flg_indice_cob_2_hh AS transunion_has_household_index_charge_2,
    flg_indice_cob_3_hh AS transunion_has_household_index_charge_3,
    flg_indice_cob_4_hh AS transunion_has_household_index_charge_4,
    flg_indice_cob_5_hh AS transunion_has_household_index_charge_5,
    flg_indice_ecom_1_hh AS transunion_has_household_index_ecom_1,
    flg_indice_ecom_2_hh AS transunion_has_household_index_ecom_2,
    flg_indice_ecom_3_hh AS transunion_has_household_index_ecom_3,
    flg_indice_ecom_4_hh AS transunion_has_household_index_ecom_4,
    flg_indice_ecom_5_hh AS transunion_has_household_index_ecom_5,
    flg_indice_fin_1_hh AS transunion_has_household_index_fin_1,
    flg_indice_fin_2_hh AS transunion_has_household_index_fin_2,
    flg_indice_fin_3_hh AS transunion_has_household_index_fin_3,
    flg_indice_fin_4_hh AS transunion_has_household_index_fin_4,
    flg_indice_fin_5_hh AS transunion_has_household_index_fin_5,
    flg_indice_tele_1_hh AS transunion_has_household_index_tele_1,
    flg_indice_tele_2_hh AS transunion_has_household_index_tele_2,
    flg_indice_tele_3_hh AS transunion_has_household_index_tele_3,
    flg_indice_tele_4_hh AS transunion_has_household_index_tele_4,
    flg_indice_tele_5_hh AS transunion_has_household_index_tele_5,
    flg_medio_compl_hh AS transunion_has_household_gt_high_school,
    flg_qsa_hh AS transunion_has_household_qsa,
    flg_rest_agencia_alta_renda AS transunion_has_high_income_class,
    flg_superior_compl_hh AS transunion_has_household_gt_graduate,
    flag_bolsa_familia AS transunion_has_bolsa_familia
  FROM
    datalake_static_files_raw.bureaus_transunion_historical_raw
),

integration_report_data AS (
  SELECT
    cpf,
    CAST(NULL AS FLOAT) AS transunion_presumed_income,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - class_banc_ult_decl") AS FLOAT) AS transunion_irpf_last_decl_class,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - ind_estab_emprego") AS FLOAT) AS transunion_index_job_stability,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_12") AS FLOAT) AS transunion_index_seg_12,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_12_cob") AS FLOAT) AS transunion_index_seg_12_charge,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_12_ecom") AS FLOAT) AS transunion_index_seg_12_ecom,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_12_fin") AS FLOAT) AS transunion_index_seg_12_fin,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_12_tele") AS FLOAT) AS transunion_index_seg_12_tele,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_24") AS FLOAT) AS transunion_index_seg_24,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_24_cob") AS FLOAT) AS transunion_index_seg_24_charge,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_24_ecom") AS FLOAT) AS transunion_index_seg_24_ecom,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_24_fin") AS FLOAT) AS transunion_index_seg_24_fin,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_24_tele") AS FLOAT) AS transunion_index_seg_24_tele,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_6") AS FLOAT) AS transunion_index_seg_6,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_6_cob") AS FLOAT) AS transunion_index_seg_6_cob,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_6_ecom") AS FLOAT) AS transunion_index_seg_6_ecom,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_6_fin") AS FLOAT) AS transunion_index_seg_6_fin,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - indic_seg_6_tele") AS FLOAT) AS transunion_index_seg_6_tele,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - porte_empregador") AS FLOAT) AS transunion_employer_size,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - sc_situacao") AS FLOAT) AS transunion_sc_situation,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - automoveis_percap_m_munic") AS FLOAT) AS transunion_percap_m_munic_cars,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - caminhao_percap_m_munic") AS FLOAT) AS transunion_percap_m_munic_trucks,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - caminonete_percap_m_munic") AS FLOAT) AS transunion_percap_m_munic_pickups,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - utilitario_percap_m_munic") AS FLOAT) AS transunion_percap_m_munic_utilitario,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - veic_outros_percap_m_munic") AS FLOAT) AS transunion_percap_m_munic_others,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - dist_centro_m") AS FLOAT) AS transunion_dist_cep_to_city_center,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - dist_fronteira_m") AS FLOAT) AS transunion_dist_cep_to_nearest_border,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - dist_risco_m") AS FLOAT) AS transunion_dist_cep_to_nearest_subnormal_aglomerate,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - idade_media") AS FLOAT) AS transunion_avg_cep_residents_age,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - idhm") AS FLOAT) AS transunion_idhm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - leito_priv_percap_mm_munic") AS FLOAT) AS transunion_percap_mm_munic_private_hosp_beds,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - leito_pub_percap_mm_munic") AS FLOAT) AS transunion_percap_mm_munic_public_hosp_beds,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - leito_sus_percap_mm_munic") AS FLOAT) AS transunion_percap_mm_munic_sus_hosp_beds,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - max_decl_10_hh") AS FLOAT) AS transunion_max_household_irpf_decl_10_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - max_decl_3_hh") AS FLOAT) AS transunion_max_household_irpf_decl_3_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - max_decl_6_hh") AS FLOAT) AS transunion_max_household_irpf_decl_6_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - max_idade_hh") AS FLOAT) AS transunion_max_household_age,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - max_ind_estab_emprego_hh") AS FLOAT) AS transunion_max_household_index_job_stability,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - max_porte_empregador_hh") AS FLOAT) AS transunion_max_household_employer_size,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - max_porte_qsa_hh") AS FLOAT) AS transunion_max_household_qsa_size,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - max_renda_pres_hh") AS FLOAT) AS transunion_max_household_presumed_income,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - media_idade_hh") AS FLOAT) AS transunion_avg_household_age,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - media_renda_pres_hh") AS FLOAT) AS transunion_avg_household_presumed_income,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - media_renda_presumida") AS FLOAT) AS transunion_avg_cep_residents_presumed_income,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - min_idade_hh") AS FLOAT) AS transunion_min_household_age,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - min_renda_pres_hh") AS FLOAT) AS transunion_min_household_presumed_income,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - moto_percap_m_munic") AS FLOAT) AS transunion_percap_m_munic_motorcycles,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_00_17") AS FLOAT) AS transunion_percent_cep_residents_00_17_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_18_29") AS FLOAT) AS transunion_percent_cep_residents_18_29_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_30_39") AS FLOAT) AS transunion_percent_cep_residents_30_39_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_40_49") AS FLOAT) AS transunion_percent_cep_residents_40_49_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_50_59") AS FLOAT) AS transunion_percent_cep_residents_50_59_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_60_69") AS FLOAT) AS transunion_percent_cep_residents_60_69_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_70_mais") AS FLOAT) AS transunion_percent_cep_residents_gt_70_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_bolsa_familia") AS FLOAT) AS transunion_percent_cep_residents_bolsa_familia,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_10_00") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_10_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_10_01") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_10_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_10_02_04") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_10_02_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_10_05_09") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_10_05_09,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_10_10") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_10_10,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_pagar_10_00") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_pend_10_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_pagar_10_01") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_pend_10_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_pagar_10_02_04") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_pend_10_02_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_pagar_10_05_09") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_pend_10_05_09,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_pagar_10_10") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_pend_10_10,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_rest_10_00") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_rest_10_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_rest_10_01") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_rest_10_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_rest_10_02_04") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_rest_10_02_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_rest_10_05_09") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_rest_10_05_09,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_decl_rest_10_10") AS FLOAT) AS transunion_percent_cep_residents_irpf_decl_rest_10_10,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_escol_00") AS FLOAT) AS transunion_percent_cep_residents_escol_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_escol_01") AS FLOAT) AS transunion_percent_cep_residents_escol_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_escol_02") AS FLOAT) AS transunion_percent_cep_residents_escol_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_escol_03") AS FLOAT) AS transunion_percent_cep_residents_escol_03,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_escol_04") AS FLOAT) AS transunion_percent_cep_residents_escol_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_escol_05") AS FLOAT) AS transunion_percent_cep_residents_escol_05,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_escol_06") AS FLOAT) AS transunion_percent_cep_residents_escol_06,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_escol_07") AS FLOAT) AS transunion_percent_cep_residents_escol_07,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_escol_08") AS FLOAT) AS transunion_percent_cep_residents_escol_08,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_escol_09") AS FLOAT) AS transunion_percent_cep_residents_escol_09,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_escol_10") AS FLOAT) AS transunion_percent_cep_residents_escol_10,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_func_pub") AS FLOAT) AS transunion_percent_cep_residents_public_employee,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_indic_00") AS FLOAT) AS transunion_percent_cep_residents_registration_rules_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_indic_01") AS FLOAT) AS transunion_percent_cep_residents_registration_rules_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_indic_02") AS FLOAT) AS transunion_percent_cep_residents_registration_rules_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_indic_03") AS FLOAT) AS transunion_percent_cep_residents_registration_rules_03,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_indic_04") AS FLOAT) AS transunion_percent_cep_residents_registration_rules_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_pop_urbana_munic") AS FLOAT) AS transunion_percent_urban_population_munic,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_renda_01") AS FLOAT) AS transunion_percent_cep_residents_presumed_income_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_renda_02") AS FLOAT) AS transunion_percent_cep_residents_presumed_income_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_renda_03") AS FLOAT) AS transunion_percent_cep_residents_presumed_income_03,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_renda_04") AS FLOAT) AS transunion_percent_cep_residents_presumed_income_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_renda_05") AS FLOAT) AS transunion_percent_cep_residents_presumed_income_05,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_renda_06") AS FLOAT) AS transunion_percent_cep_residents_presumed_income_06,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_renda_07") AS FLOAT) AS transunion_percent_cep_residents_presumed_income_07,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_alto") AS FLOAT) AS transunion_percent_cep_residents_seg_high,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_baixo") AS FLOAT) AS transunion_percent_cep_residents_seg_low,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_medio") AS FLOAT) AS transunion_percent_cep_residents_seg_mid,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_cob_alto") AS FLOAT) AS transunion_percent_cep_residents_seg_charge_high,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_cob_baixo") AS FLOAT) AS transunion_percent_cep_residents_seg_charge_low,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_cob_medio") AS FLOAT) AS transunion_percent_cep_residents_seg_charge_mid,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_ecom_alto") AS FLOAT) AS transunion_percent_cep_residents_seg_ecom_high,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_ecom_baixo") AS FLOAT) AS transunion_percent_cep_residents_seg_ecom_low,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_ecom_medio") AS FLOAT) AS transunion_percent_cep_residents_seg_ecom_mid,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_fin_alto") AS FLOAT) AS transunion_percent_cep_residents_seg_fin_high,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_fin_baixo") AS FLOAT) AS transunion_percent_cep_residents_seg_fin_low,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_fin_medio") AS FLOAT) AS transunion_percent_cep_residents_seg_fin_mid,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_muito_alto") AS FLOAT) AS transunion_percent_cep_residents_seg_very_high,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_muito_baixo") AS FLOAT) AS transunion_percent_cep_residents_seg_very_low,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_tele_alto") AS FLOAT) AS transunion_percent_cep_residents_seg_tele_high,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_tele_baixo") AS FLOAT) AS transunion_percent_cep_residents_seg_tele_low,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_tele_medio") AS FLOAT) AS transunion_percent_cep_residents_seg_tele_mid,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_tele_muito_alto") AS FLOAT) AS transunion_percent_cep_residents_seg_tele_very_high,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_segmento_tele_muito_baixo") AS FLOAT) AS transunion_percent_cep_residents_seg_tele_very_low,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_sexo_f") AS FLOAT) AS transunion_percent_cep_residents_female,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - percent_sexo_m") AS FLOAT) AS transunion_percent_cep_residents_male,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - pib_perc_munic") AS FLOAT) AS transunion_percap_pib_munic,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - pib_percent_agro_munic") AS FLOAT) AS transunion_percent_pib_agro_munic,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - pib_percent_ind_munic") AS FLOAT) AS transunion_percent_pib_ind_munic,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - pib_percent_serv_munic") AS FLOAT) AS transunion_percent_pib_serv_munic,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_decl_10") AS FLOAT) AS transunion_qtd_irpf_decl_10_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_decl_3") AS FLOAT) AS transunion_qtd_irpf_decl_3_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_decl_6") AS FLOAT) AS transunion_qtd_irpf_decl_6_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_decl_isento") AS FLOAT) AS transunion_qtd_irpf_decl_isento,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_decl_pagar_10") AS FLOAT) AS transunion_qtd_irpf_decl_pend_10_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_decl_pagar_3") AS FLOAT) AS transunion_qtd_irpf_decl_pend_3_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_decl_pagar_6") AS FLOAT) AS transunion_qtd_irpf_decl_pend_6_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_decl_rest_10") AS FLOAT) AS transunion_qtd_irpf_decl_rest_10_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_decl_rest_3") AS FLOAT) AS transunion_qtd_irpf_decl_rest_3_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_decl_rest_6") AS FLOAT) AS transunion_qtd_irpf_decl_rest_6_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_email") AS FLOAT) AS transunion_qtd_doc_distinct_emails,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_endereco") AS FLOAT) AS transunion_qtd_doc_distinct_addresses,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_ind_estab_emprego_hh") AS FLOAT) AS transunion_qtd_household_index_job_stability,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_pessoas_hh") AS FLOAT) AS transunion_qtd_household_persons,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_tel_cel") AS FLOAT) AS transunion_qtd_doc_distinct_tel_cel,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - qtd_tel_fixo") AS FLOAT) AS transunion_qtd_doc_distinct_tel_fixo,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_idade_media") AS FLOAT) AS transunion_avg_sc_age,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_media_morador") AS FLOAT) AS transunion_avg_sc_resident,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_media_renda_presumida") AS FLOAT) AS transunion_avg_sc_presumed_income,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_00_17") AS FLOAT) AS transunion_percent_sc_00_17_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_18_29") AS FLOAT) AS transunion_percent_sc_18_29_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_30_39") AS FLOAT) AS transunion_percent_sc_30_39_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_40_49") AS FLOAT) AS transunion_percent_sc_40_49_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_50_59") AS FLOAT) AS transunion_percent_sc_50_59_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_60_69") AS FLOAT) AS transunion_percent_sc_60_69_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_70_95") AS FLOAT) AS transunion_percent_sc_70_95_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_bolsa_familia") AS FLOAT) AS transunion_percent_sc_bolsa_familia,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_00") AS FLOAT) AS transunion_percent_sc_consultas_12_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_01") AS FLOAT) AS transunion_percent_sc_consultas_12_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_02") AS FLOAT) AS transunion_percent_sc_consultas_12_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_03") AS FLOAT) AS transunion_percent_sc_consultas_12_03,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_04") AS FLOAT) AS transunion_percent_sc_consultas_12_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_cob_00") AS FLOAT) AS transunion_percent_sc_consultas_12_charge_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_cob_01") AS FLOAT) AS transunion_percent_sc_consultas_12_charge_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_cob_02") AS FLOAT) AS transunion_percent_sc_consultas_12_charge_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_ecom_00") AS FLOAT) AS transunion_percent_sc_consultas_12_ecom_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_ecom_01") AS FLOAT) AS transunion_percent_sc_consultas_12_ecom_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_ecom_02") AS FLOAT) AS transunion_percent_sc_consultas_12_ecom_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_fin_00") AS FLOAT) AS transunion_percent_sc_consultas_12_fin_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_fin_01") AS FLOAT) AS transunion_percent_sc_consultas_12_fin_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_fin_02") AS FLOAT) AS transunion_percent_sc_consultas_12_fin_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_tele_00") AS FLOAT) AS transunion_percent_sc_consultas_12_tele_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_tele_01") AS FLOAT) AS transunion_percent_sc_consultas_12_tele_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_tele_02") AS FLOAT) AS transunion_percent_sc_consultas_12_tele_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_tele_03") AS FLOAT) AS transunion_percent_sc_consultas_12_tele_03,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_consultas_12_tele_04") AS FLOAT) AS transunion_percent_sc_consultas_12_tele_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_10_00") AS FLOAT) AS transunion_percent_sc_irpf_decl_10_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_10_01") AS FLOAT) AS transunion_percent_sc_irpf_decl_10_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_10_02") AS FLOAT) AS transunion_percent_sc_irpf_decl_10_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_10_03") AS FLOAT) AS transunion_percent_sc_irpf_decl_10_03,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_10_04") AS FLOAT) AS transunion_percent_sc_irpf_decl_10_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_pagar_10_00") AS FLOAT) AS transunion_percent_sc_irpf_decl_pend_10_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_pagar_10_01") AS FLOAT) AS transunion_percent_sc_irpf_decl_pend_10_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_pagar_10_02") AS FLOAT) AS transunion_percent_sc_irpf_decl_pend_10_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_pagar_10_03") AS FLOAT) AS transunion_percent_sc_irpf_decl_pend_10_03,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_pagar_10_04") AS FLOAT) AS transunion_percent_sc_irpf_decl_pend_10_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_rest_10_00") AS FLOAT) AS transunion_percent_sc_irpf_decl_rest_10_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_rest_10_01") AS FLOAT) AS transunion_percent_sc_irpf_decl_rest_10_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_rest_10_02") AS FLOAT) AS transunion_percent_sc_irpf_decl_rest_10_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_rest_10_03") AS FLOAT) AS transunion_percent_sc_irpf_decl_rest_10_03,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_decl_rest_10_04") AS FLOAT) AS transunion_percent_sc_irpf_decl_rest_10_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_1_banheiro") AS FLOAT) AS transunion_percent_sc_residence_1_bathroom,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_1_morador") AS FLOAT) AS transunion_percent_sc_residence_1_resident,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_2_banheiros") AS FLOAT) AS transunion_percent_sc_residence_2_bathrooms,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_2_morador") AS FLOAT) AS transunion_percent_sc_residence_2_residents,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_3_morador") AS FLOAT) AS transunion_percent_sc_residence_3_residents,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_4_morador") AS FLOAT) AS transunion_percent_sc_residence_4_residents,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_adquiridos_outras_formas") AS FLOAT) AS transunion_percent_sc_residence_other_ways,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_agua_rede_geral") AS FLOAT) AS transunion_percent_sc_residence_water_supply,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_alugados") AS FLOAT) AS transunion_percent_sc_residence_rent,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_apartamento") AS FLOAT) AS transunion_percent_sc_residence_apartments,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_banheiro_uso_exclusivo") AS FLOAT) AS transunion_percent_sc_residence_exclusive_bathroom,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_casa") AS FLOAT) AS transunion_percent_sc_residence_houses,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_casa_em_condominio_vila") AS FLOAT) AS transunion_percent_sc_residence_condo_houses,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_coleta_lixo") AS FLOAT) AS transunion_percent_sc_residence_garbage_collection,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_coletado_cacamba") AS FLOAT) AS transunion_percent_sc_residence_garbage_collection_cacamba,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_coletado_outras_formas") AS FLOAT) AS transunion_percent_sc_residence_garbage_collection_other_ways,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_coletado_servico_limpeza") AS FLOAT) AS transunion_percent_sc_residence_garbage_collection_cleanup_service,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_com_esgoto_ceu_aberto") AS FLOAT) AS transunion_percent_sc_residence_open_sewer,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_com_lixo_acumulado") AS FLOAT) AS transunion_percent_sc_residence_accumulated_garbage,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_em_aquisicao") AS FLOAT) AS transunion_percent_sc_residence_in_acquiring,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_energia_eletrica") AS FLOAT) AS transunion_percent_sc_residence_electrical_supply,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_energia_eletrica_medidor_compartil") AS FLOAT) AS transunion_percent_sc_residence_energy_meter_shared,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_energia_eletrica_medidor_exclusivo") AS FLOAT) AS transunion_percent_sc_residence_energy_meter_exclusive,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_energia_eletrica_outras_formas") AS FLOAT) AS transunion_percent_sc_residence_energy_meter_other_ways,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_energia_eletrica_rede_distribuicao") AS FLOAT) AS transunion_percent_sc_residence_power_distribution_network,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_energia_eletrica_sem_medidor") AS FLOAT) AS transunion_percent_sc_residence_energy_meter_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_esgoto_demais") AS FLOAT) AS transunion_percent_sc_residence_sewage_too_much,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_esgoto_fossa_septica") AS FLOAT) AS transunion_percent_sc_residence_sewage_septic_tank,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_esgoto_rede_publica") AS FLOAT) AS transunion_percent_sc_residence_sewage_public_network,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_mais_2_banheiros") AS FLOAT) AS transunion_percent_sc_residence_gt_2_bathrooms,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_mais_4_morador") AS FLOAT) AS transunion_percent_sc_residence_gt_4_residents,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_moradia_adequada") AS FLOAT) AS transunion_percent_sc_residence_adequate_housing,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_moradia_inadequada") AS FLOAT) AS transunion_percent_sc_residence_inadequate_housing,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_moradia_semi_adequada") AS FLOAT) AS transunion_percent_sc_residence_semi_adequate_housing,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_permanentes") AS FLOAT) AS transunion_percent_sc_residence_permanent_residents,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_quitados") AS FLOAT) AS transunion_percent_sc_residence_paid_off,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_rendimento_mensal_acima_10_sm") AS FLOAT) AS transunion_percent_sc_residence_monthly_income_gt_10sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_rendimento_mensal_ate_1s8_sm") AS FLOAT) AS transunion_percent_sc_residence_monthly_income_until_1s8_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_rendimento_mensal_de_1_a_2_sm") AS FLOAT) AS transunion_percent_sc_residence_monthly_income_1_a_2_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_rendimento_mensal_de_1s2_a_1_sm") AS FLOAT) AS transunion_percent_sc_residence_monthly_income_1s2_a_1_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_rendimento_mensal_de_1s4_a_1s2_sm") AS FLOAT) AS transunion_percent_sc_residence_monthly_income_1s4_a_1s2_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_rendimento_mensal_de_1s8_a_1s4_sm") AS FLOAT) AS transunion_percent_sc_residence_monthly_income_1s8_a_1s4_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_rendimento_mensal_de_2_a_3_sm") AS FLOAT) AS transunion_percent_sc_residence_monthly_income_2_a_3_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_rendimento_mensal_de_3_a_5_sm") AS FLOAT) AS transunion_percent_sc_residence_monthly_income_3_a_5_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_rendimento_mensal_de_5_a_10_sm") AS FLOAT) AS transunion_percent_sc_residence_monthly_income_5_a_10_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_sem_arborizacao") AS FLOAT) AS transunion_percent_sc_residence_afforestation_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_sem_bueiro") AS FLOAT) AS transunion_percent_sc_residence_manhole_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_sem_calcada") AS FLOAT) AS transunion_percent_sc_residence_sidewalk_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_sem_guia") AS FLOAT) AS transunion_percent_sc_residence_curb_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_sem_identificacao_logradouro") AS FLOAT) AS transunion_percent_sc_residence_public_place_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_sem_iluminacao_publica") AS FLOAT) AS transunion_percent_sc_residence_public_energy_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_sem_morador_feminino") AS FLOAT) AS transunion_percent_sc_residence_female_resident_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_sem_morador_masculino") AS FLOAT) AS transunion_percent_sc_residence_male_resident_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_sem_pavimentacao") AS FLOAT) AS transunion_percent_sc_residence_paving_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_sem_rampa_acessibilidade") AS FLOAT) AS transunion_percent_sc_residence_accessibility_ramp_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_domici_sem_rendimento_mensal") AS FLOAT) AS transunion_percent_sc_residence_monthly_income_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_escol_00") AS FLOAT) AS transunion_percent_sc_escol_00,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_escol_01") AS FLOAT) AS transunion_percent_sc_escol_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_escol_02") AS FLOAT) AS transunion_percent_sc_escol_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_escol_03") AS FLOAT) AS transunion_percent_sc_escol_03,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_escol_04") AS FLOAT) AS transunion_percent_sc_escol_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_escol_05") AS FLOAT) AS transunion_percent_sc_escol_05,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_escol_06") AS FLOAT) AS transunion_percent_sc_escol_06,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_escol_07") AS FLOAT) AS transunion_percent_sc_escol_07,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_escol_08") AS FLOAT) AS transunion_percent_sc_escol_08,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_escol_09") AS FLOAT) AS transunion_percent_sc_escol_09,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_escol_10") AS FLOAT) AS transunion_percent_sc_escol_10,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_func_pub") AS FLOAT) AS transunion_percent_sc_public_employee,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_agua_rede_geral") AS FLOAT) AS transunion_percent_sc_resident_water_supply,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_apartamento") AS FLOAT) AS transunion_percent_sc_resident_apartment,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_casa") AS FLOAT) AS transunion_percent_sc_resident_house,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_casa_condominio_vila") AS FLOAT) AS transunion_percent_sc_resident_condo_house,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_coleta_lixo") AS FLOAT) AS transunion_percent_sc_resident_garbage_collection,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_coleta_lixo_servico") AS FLOAT) AS transunion_percent_sc_resident_gargabe_collection_service,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_domici_adquiridos_outras_formas") AS FLOAT) AS transunion_percent_sc_resident_residence_acquired_other_ways,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_domici_alugado") AS FLOAT) AS transunion_percent_sc_resident_residence_rent,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_domici_em_aquisicao") AS FLOAT) AS transunion_percent_sc_resident_residence_in_acquisition,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_domici_permanente") AS FLOAT) AS transunion_percent_sc_resident_residence_permanent,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_domici_quitado") AS FLOAT) AS transunion_percent_sc_resident_residence_paid_off,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_morador_energia_eletrica") AS FLOAT) AS transunion_percent_sc_resident_residence_electrical_supply,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_0_4_anos") AS FLOAT) AS transunion_percent_people_0_4_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_10_14_anos") AS FLOAT) AS transunion_percent_people_10_14_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_15_17_anos") AS FLOAT) AS transunion_percent_people_15_17_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_18_19_anos") AS FLOAT) AS transunion_percent_people_18_19_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_20_24_anos") AS FLOAT) AS transunion_percent_people_20_24_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_25_29_anos") AS FLOAT) AS transunion_percent_people_25_29_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_30_34_anos") AS FLOAT) AS transunion_percent_people_30_34_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_35_39_anos") AS FLOAT) AS transunion_percent_people_35_39_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_40_44_anos") AS FLOAT) AS transunion_percent_people_40_44_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_45_49_anos") AS FLOAT) AS transunion_percent_people_45_49_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_50_54_anos") AS FLOAT) AS transunion_percent_people_50_54_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_55_59_anos") AS FLOAT) AS transunion_percent_people_55_59_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_5_9_anos") AS FLOAT) AS transunion_percent_people_5_9_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_60_69_anos") AS FLOAT) AS transunion_percent_people_60_69_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_com_registro_nascimento") AS FLOAT) AS transunion_percent_people_registration_birth,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_mais_69_anos") AS FLOAT) AS transunion_percent_people_gt_69_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_nao_sabem_registro_nascimento") AS FLOAT) AS transunion_percent_people_registration_birth_not_known,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_rendimento_mensal_10_a_15_sm") AS FLOAT) AS transunion_percent_people_monthly_income_10_a_15_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_rendimento_mensal_15_a_20_sm") AS FLOAT) AS transunion_percent_people_monthly_income_15_a_20_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_rendimento_mensal_1_a_2_sm") AS FLOAT) AS transunion_percent_people_monthly_income_1_a_2_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_rendimento_mensal_1s2_a_1_sm") AS FLOAT) AS transunion_percent_people_monthly_income_1s2_a_1_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_rendimento_mensal_2_a_3_sm") AS FLOAT) AS transunion_percent_people_monthly_income_2_a_3_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_rendimento_mensal_3_a_5_sm") AS FLOAT) AS transunion_percent_people_monthly_income_3_a_5_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_rendimento_mensal_5_a_10_sm") AS FLOAT) AS transunion_percent_people_monthly_income_5_a_10_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_rendimento_mensal_acima_20_sm") AS FLOAT) AS transunion_percent_people_monthly_income_gt_20_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_rendimento_mensal_ate_1s2_sm") AS FLOAT) AS transunion_percent_people_monthly_income_until_1s2_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_sem_registro_nascimento") AS FLOAT) AS transunion_percent_people_registration_birth_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_pessoas_sem_rendimento_mensal") AS FLOAT) AS transunion_percent_people_monthly_income_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_renda_01") AS FLOAT) AS transunion_percent_sc_income_01,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_renda_02") AS FLOAT) AS transunion_percent_sc_income_02,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_renda_03") AS FLOAT) AS transunion_percent_sc_income_03,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_renda_04") AS FLOAT) AS transunion_percent_sc_income_04,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_renda_05") AS FLOAT) AS transunion_percent_sc_income_05,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_renda_06") AS FLOAT) AS transunion_percent_sc_income_06,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_renda_07") AS FLOAT) AS transunion_percent_sc_income_07,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_domici_alfabetizado_feminino") AS FLOAT) AS transunion_percent_sc_responsible_person_literate_female,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_domici_alfabetizado_masculino") AS FLOAT) AS transunion_percent_sc_responsible_person_literate_male,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_domici_sexo_feminino") AS FLOAT) AS transunion_percent_sc_responsible_person_female,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_domici_sexo_masculino") AS FLOAT) AS transunion_percent_sc_responsible_person_male,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_rendimento_mensal_10_a_15_sm") AS FLOAT) AS transunion_percent_sc_responsible_person_monthly_income_10_a_15_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_rendimento_mensal_15_a_20_sm") AS FLOAT) AS transunion_percent_sc_responsible_person_monthly_income_15_a_20_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_rendimento_mensal_1_a_2_sm") AS FLOAT) AS transunion_percent_sc_responsible_person_monthly_income_1_a_2_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_rendimento_mensal_1s2_a_1_sm") AS FLOAT) AS transunion_percent_sc_responsible_person_monthly_income_1s2_a_1_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_rendimento_mensal_2_a_3_sm") AS FLOAT) AS transunion_percent_sc_responsible_person_monthly_income_2_a_3_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_rendimento_mensal_3_a_5_sm") AS FLOAT) AS transunion_percent_sc_responsible_person_monthly_income_3_a_5_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_rendimento_mensal_5_a_10_sm") AS FLOAT) AS transunion_percent_sc_responsible_person_monthly_income_5_a_10_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_rendimento_mensal_acima_20_sm") AS FLOAT) AS transunion_percent_sc_responsible_person_monthly_income_gt_20_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_rendimento_mensal_ate_1s2_sm") AS FLOAT) AS transunion_percent_sc_responsible_person_monthly_income_until_1s2_sm,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_responsa_sem_rendimento_mensal") AS FLOAT) AS transunion_percent_sc_responsible_person_monthly_income_without,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_sexo_f") AS FLOAT) AS transunion_percent_sc_female,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percent_sexo_m") AS FLOAT) AS transunion_percent_sc_male,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_percentual_qsa") AS FLOAT) AS transunion_percent_sc_qsa,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_rendimento_medio_mensal_domici_salario_minimo") AS FLOAT) AS transunion_percent_sc_residence_avg_monthly_income_salario_minimo,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_rendimento_medio_mensal_respons_domici_salario_minimo") AS FLOAT) AS transunion_percent_sc_responsible_person_avg_monthly_income_salario_minimo,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_valor_rendimento_mensal_pessoas_sm") AS FLOAT) AS transunion_sum_sc_persons_monthly_income_gt_10_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sc_valor_rendimento_mensal_responsa_sm") AS FLOAT) AS transunion_sum_sc_responsible_persons_monthly_income,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - sum_renda_pres_hh") AS FLOAT) AS transunion_sum_household_presumed_income,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - tempo_emissao_cpf") AS FLOAT) AS transunion_time_cpf_emission,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - tmp_meses_ult_tel_cel") AS FLOAT) AS transunion_time_months_last_cel_phone,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - tmp_meses_ult_tel_fixo") AS FLOAT) AS transunion_time_months_last_tel_fixo,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - tmp_ult_decl_a_restit") AS FLOAT) AS transunion_time_last_irpf_decl_rest,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - tmpo_ult_decl") AS FLOAT) AS transunion_time_last_irpf_decl,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - tmpo_ult_decl_a_pagar") AS FLOAT) AS transunion_time_last_irpf_decl_pend,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_11_15_anos_hh") AS FLOAT) AS transunion_has_household_11_15_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_16_17_anos_hh") AS FLOAT) AS transunion_has_household_16_17_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_18_20_anos_hh") AS FLOAT) AS transunion_has_household_18_20_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_21_25_anos_hh") AS FLOAT) AS transunion_has_household_21_25_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_25_30_anos_hh") AS FLOAT) AS transunion_has_household_25_30_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_3_5_anos_hh") AS FLOAT) AS transunion_has_household_3_5_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_6_10_anos_hh") AS FLOAT) AS transunion_has_household_6_10_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_ate_2_anos_hh") AS FLOAT) AS transunion_has_household_until_2_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_func_pub") AS FLOAT) AS transunion_is_public_employee,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_socio") AS FLOAT) AS transunion_is_business_partner,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_tel_cel_procon") AS FLOAT) AS transunion_is_tel_cel_procon,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_tel_fixo_assin") AS FLOAT) AS transunion_is_tel_fixo_assin,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flag_tel_fixo_procon") AS FLOAT) AS transunion_is_tel_fixo_procon,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_bolsa_familia_hh") AS FLOAT) AS transunion_has_household_bolsa_familia,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_decl_10_hh") AS FLOAT) AS transunion_has_household_irpf_decl_10_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_decl_3_hh") AS FLOAT) AS transunion_has_household_irpf_decl_3_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_decl_6_hh") AS FLOAT) AS transunion_has_household_irpf_decl_6_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_decl_pagar_10_hh") AS FLOAT) AS transunion_has_household_irpf_decl_pend_10_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_decl_pagar_3_hh") AS FLOAT) AS transunion_has_household_irpf_decl_pend_3_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_decl_pagar_6_hh") AS FLOAT) AS transunion_has_household_irpf_decl_pend_6_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_decl_rest_10a_hh") AS FLOAT) AS transunion_has_household_irpf_decl_rest_10_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_decl_rest_3a_hh") AS FLOAT) AS transunion_has_household_irpf_decl_rest_3_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_decl_rest_6a_hh") AS FLOAT) AS transunion_has_household_irpf_decl_rest_6_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_func_pub_hh") AS FLOAT) AS transunion_has_household_public_employee,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_idade_35_hh") AS FLOAT) AS transunion_has_household_gt_35_years,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_ind_estab_emprego_hh") AS FLOAT) AS transunion_has_household_index_job_stability,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indicador_hh") AS FLOAT) AS transunion_has_household_invalid_registration_rules,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_cob_1_hh") AS FLOAT) AS transunion_has_household_index_charge_1,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_cob_2_hh") AS FLOAT) AS transunion_has_household_index_charge_2,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_cob_3_hh") AS FLOAT) AS transunion_has_household_index_charge_3,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_cob_4_hh") AS FLOAT) AS transunion_has_household_index_charge_4,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_cob_5_hh") AS FLOAT) AS transunion_has_household_index_charge_5,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_ecom_1_hh") AS FLOAT) AS transunion_has_household_index_ecom_1,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_ecom_2_hh") AS FLOAT) AS transunion_has_household_index_ecom_2,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_ecom_3_hh") AS FLOAT) AS transunion_has_household_index_ecom_3,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_ecom_4_hh") AS FLOAT) AS transunion_has_household_index_ecom_4,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_ecom_5_hh") AS FLOAT) AS transunion_has_household_index_ecom_5,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_fin_1_hh") AS FLOAT) AS transunion_has_household_index_fin_1,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_fin_2_hh") AS FLOAT) AS transunion_has_household_index_fin_2,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_fin_3_hh") AS FLOAT) AS transunion_has_household_index_fin_3,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_fin_4_hh") AS FLOAT) AS transunion_has_household_index_fin_4,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_fin_5_hh") AS FLOAT) AS transunion_has_household_index_fin_5,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_tele_1_hh") AS FLOAT) AS transunion_has_household_index_tele_1,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_tele_2_hh") AS FLOAT) AS transunion_has_household_index_tele_2,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_tele_3_hh") AS FLOAT) AS transunion_has_household_index_tele_3,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_tele_4_hh") AS FLOAT) AS transunion_has_household_index_tele_4,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_indice_tele_5_hh") AS FLOAT) AS transunion_has_household_index_tele_5,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_medio_compl_hh") AS FLOAT) AS transunion_has_household_gt_high_school,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_qsa_hh") AS FLOAT) AS transunion_has_household_qsa,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_rest_agencia_alta_renda") AS FLOAT) AS transunion_has_high_income_class,
    CAST(GET_JSON_OBJECT(attributes, "$.Discreta - flg_superior_compl_hh") AS FLOAT) AS transunion_has_household_gt_graduate,
    CAST(GET_JSON_OBJECT(attributes, "$.Valor - flag_bolsa_familia") AS FLOAT) AS transunion_has_bolsa_familia,
    revinfo.ts_created AS timestamp
  FROM 
    datalake_arquivo_confidencial_clean.integration_report_aud AS itr
  JOIN
    datalake_arquivo_confidencial_clean.rev_info AS revinfo
      ON itr.rev = revinfo.rev
  WHERE
    integration_provider = 'TRANSUNION_BOOK3D'
    AND attributes IS NOT NULL
    AND GET_JSON_OBJECT(attributes, "$.Erro na consulta") = False
),

last_credit_analysis AS (
  SELECT
    id_proposal,
    MAX(ts_created) AS last_ca_timestamp
  FROM
    datalake_sorting_hat_clean.credit_analysis 
  GROUP BY id_proposal
),

enriched_integration_report_data AS (
  SELECT
    l_ca.id_proposal,
    ppt.id AS id_proponent,
    itr.*,
    l_ca.last_ca_timestamp,
    MAX(itr.timestamp) OVER(PARTITION BY l_ca.id_proposal, ppt.id, ppt.cpf) AS max_itr_timestamp
  FROM
    datalake_sorting_hat_clean.proposal AS pps
    JOIN
      datalake_sorting_hat_clean.proponent AS ppt
        ON pps.id = ppt.id_proposal
    JOIN
      last_credit_analysis AS l_ca
        ON pps.id = l_ca.id_proposal
    JOIN
      integration_report_data AS itr
        ON itr.cpf = REPLACE(REPLACE(ppt.cpf,".",""),"-","")
        AND itr.timestamp < l_ca.last_ca_timestamp
),

internal_data AS (
  SELECT
    *
  FROM 
    enriched_integration_report_data
  WHERE
    max_itr_timestamp = timestamp
    AND DATEDIFF(last_ca_timestamp, max_itr_timestamp) < 30
)

SELECT
  COALESCE(
    btest.id_proposal,
    idata.id_proposal
  ) AS id_proposal,
  COALESCE(
    btest.id_proponent,
    idata.id_proponent
  ) AS id_proponent,
  COALESCE(
    btest.cpf,
    idata.cpf
  ) AS cpf,
  COALESCE(
    btest.transunion_presumed_income,
    idata.transunion_presumed_income
  ) AS transunion_presumed_income,
  COALESCE(
    btest.transunion_irpf_last_decl_class,
    idata.transunion_irpf_last_decl_class
  ) AS transunion_irpf_last_decl_class,
  COALESCE(
    btest.transunion_index_job_stability,
    idata.transunion_index_job_stability
  ) AS transunion_index_job_stability,
  COALESCE(
    btest.transunion_index_seg_12,
    idata.transunion_index_seg_12
  ) AS transunion_index_seg_12,
  COALESCE(
    btest.transunion_index_seg_12_charge,
    idata.transunion_index_seg_12_charge
  ) AS transunion_index_seg_12_charge,
  COALESCE(
    btest.transunion_index_seg_12_ecom,
    idata.transunion_index_seg_12_ecom
  ) AS transunion_index_seg_12_ecom,
  COALESCE(
    btest.transunion_index_seg_12_fin,
    idata.transunion_index_seg_12_fin
  ) AS transunion_index_seg_12_fin,
  COALESCE(
    btest.transunion_index_seg_12_tele,
    idata.transunion_index_seg_12_tele
  ) AS transunion_index_seg_12_tele,
  COALESCE(
    btest.transunion_index_seg_24,
    idata.transunion_index_seg_24
  ) AS transunion_index_seg_24,
  COALESCE(
    btest.transunion_index_seg_24_charge,
    idata.transunion_index_seg_24_charge
  ) AS transunion_index_seg_24_charge,
  COALESCE(
    btest.transunion_index_seg_24_ecom,
    idata.transunion_index_seg_24_ecom
  ) AS transunion_index_seg_24_ecom,
  COALESCE(
    btest.transunion_index_seg_24_fin,
    idata.transunion_index_seg_24_fin
  ) AS transunion_index_seg_24_fin,
  COALESCE(
    btest.transunion_index_seg_24_tele,
    idata.transunion_index_seg_24_tele
  ) AS transunion_index_seg_24_tele,
  COALESCE(
    btest.transunion_index_seg_6,
    idata.transunion_index_seg_6
  ) AS transunion_index_seg_6,
  COALESCE(
    btest.transunion_index_seg_6_cob,
    idata.transunion_index_seg_6_cob
  ) AS transunion_index_seg_6_cob,
  COALESCE(
    btest.transunion_index_seg_6_ecom,
    idata.transunion_index_seg_6_ecom
  ) AS transunion_index_seg_6_ecom,
  COALESCE(
    btest.transunion_index_seg_6_fin,
    idata.transunion_index_seg_6_fin
  ) AS transunion_index_seg_6_fin,
  COALESCE(
    btest.transunion_index_seg_6_tele,
    idata.transunion_index_seg_6_tele
  ) AS transunion_index_seg_6_tele,
  COALESCE(
    btest.transunion_employer_size,
    idata.transunion_employer_size
  ) AS transunion_employer_size,
  COALESCE(
    btest.transunion_sc_situation,
    idata.transunion_sc_situation
  ) AS transunion_sc_situation,
  COALESCE(
    btest.transunion_percap_m_munic_cars,
    idata.transunion_percap_m_munic_cars
  ) AS transunion_percap_m_munic_cars,
  COALESCE(
    btest.transunion_percap_m_munic_trucks,
    idata.transunion_percap_m_munic_trucks
  ) AS transunion_percap_m_munic_trucks,
  COALESCE(
    btest.transunion_percap_m_munic_pickups,
    idata.transunion_percap_m_munic_pickups
  ) AS transunion_percap_m_munic_pickups,
  COALESCE(
    btest.transunion_percap_m_munic_utilitario,
    idata.transunion_percap_m_munic_utilitario
  ) AS transunion_percap_m_munic_utilitario,
  COALESCE(
    btest.transunion_percap_m_munic_others,
    idata.transunion_percap_m_munic_others
  ) AS transunion_percap_m_munic_others,
  COALESCE(
    btest.transunion_dist_cep_to_city_center,
    idata.transunion_dist_cep_to_city_center
  ) AS transunion_dist_cep_to_city_center,
  COALESCE(
    btest.transunion_dist_cep_to_nearest_border,
    idata.transunion_dist_cep_to_nearest_border
  ) AS transunion_dist_cep_to_nearest_border,
  COALESCE(
    btest.transunion_dist_cep_to_nearest_subnormal_aglomerate,
    idata.transunion_dist_cep_to_nearest_subnormal_aglomerate
  ) AS transunion_dist_cep_to_nearest_subnormal_aglomerate,
  COALESCE(
    btest.transunion_avg_cep_residents_age,
    idata.transunion_avg_cep_residents_age
  ) AS transunion_avg_cep_residents_age,
  COALESCE(
    btest.transunion_idhm,
    idata.transunion_idhm
  ) AS transunion_idhm,
  COALESCE(
    btest.transunion_percap_mm_munic_private_hosp_beds,
    idata.transunion_percap_mm_munic_private_hosp_beds
  ) AS transunion_percap_mm_munic_private_hosp_beds,
  COALESCE(
    btest.transunion_percap_mm_munic_public_hosp_beds,
    idata.transunion_percap_mm_munic_public_hosp_beds
  ) AS transunion_percap_mm_munic_public_hosp_beds,
  COALESCE(
    btest.transunion_percap_mm_munic_sus_hosp_beds,
    idata.transunion_percap_mm_munic_sus_hosp_beds
  ) AS transunion_percap_mm_munic_sus_hosp_beds,
  COALESCE(
    btest.transunion_max_household_irpf_decl_10_years,
    idata.transunion_max_household_irpf_decl_10_years
  ) AS transunion_max_household_irpf_decl_10_years,
  COALESCE(
    btest.transunion_max_household_irpf_decl_3_years,
    idata.transunion_max_household_irpf_decl_3_years
  ) AS transunion_max_household_irpf_decl_3_years,
  COALESCE(
    btest.transunion_max_household_irpf_decl_6_years,
    idata.transunion_max_household_irpf_decl_6_years
  ) AS transunion_max_household_irpf_decl_6_years,
  COALESCE(
    btest.transunion_max_household_age,
    idata.transunion_max_household_age
  ) AS transunion_max_household_age,
  COALESCE(
    btest.transunion_max_household_index_job_stability,
    idata.transunion_max_household_index_job_stability
  ) AS transunion_max_household_index_job_stability,
  COALESCE(
    btest.transunion_max_household_employer_size,
    idata.transunion_max_household_employer_size
  ) AS transunion_max_household_employer_size,
  COALESCE(
    btest.transunion_max_household_qsa_size,
    idata.transunion_max_household_qsa_size
  ) AS transunion_max_household_qsa_size,
  COALESCE(
    btest.transunion_max_household_presumed_income,
    idata.transunion_max_household_presumed_income
  ) AS transunion_max_household_presumed_income,
  COALESCE(
    btest.transunion_avg_household_age,
    idata.transunion_avg_household_age
  ) AS transunion_avg_household_age,
  COALESCE(
    btest.transunion_avg_household_presumed_income,
    idata.transunion_avg_household_presumed_income
  ) AS transunion_avg_household_presumed_income,
  COALESCE(
    btest.transunion_avg_cep_residents_presumed_income,
    idata.transunion_avg_cep_residents_presumed_income
  ) AS transunion_avg_cep_residents_presumed_income,
  COALESCE(
    btest.transunion_min_household_age,
    idata.transunion_min_household_age
  ) AS transunion_min_household_age,
  COALESCE(
    btest.transunion_min_household_presumed_income,
    idata.transunion_min_household_presumed_income
  ) AS transunion_min_household_presumed_income,
  COALESCE(
    btest.transunion_percap_m_munic_motorcycles,
    idata.transunion_percap_m_munic_motorcycles
  ) AS transunion_percap_m_munic_motorcycles,
  COALESCE(
    btest.transunion_percent_cep_residents_00_17_years,
    idata.transunion_percent_cep_residents_00_17_years
  ) AS transunion_percent_cep_residents_00_17_years,
  COALESCE(
    btest.transunion_percent_cep_residents_18_29_years,
    idata.transunion_percent_cep_residents_18_29_years
  ) AS transunion_percent_cep_residents_18_29_years,
  COALESCE(
    btest.transunion_percent_cep_residents_30_39_years,
    idata.transunion_percent_cep_residents_30_39_years
  ) AS transunion_percent_cep_residents_30_39_years,
  COALESCE(
    btest.transunion_percent_cep_residents_40_49_years,
    idata.transunion_percent_cep_residents_40_49_years
  ) AS transunion_percent_cep_residents_40_49_years,
  COALESCE(
    btest.transunion_percent_cep_residents_50_59_years,
    idata.transunion_percent_cep_residents_50_59_years
  ) AS transunion_percent_cep_residents_50_59_years,
  COALESCE(
    btest.transunion_percent_cep_residents_60_69_years,
    idata.transunion_percent_cep_residents_60_69_years
  ) AS transunion_percent_cep_residents_60_69_years,
  COALESCE(
    btest.transunion_percent_cep_residents_gt_70_years,
    idata.transunion_percent_cep_residents_gt_70_years
  ) AS transunion_percent_cep_residents_gt_70_years,
  COALESCE(
    btest.transunion_percent_cep_residents_bolsa_familia,
    idata.transunion_percent_cep_residents_bolsa_familia
  ) AS transunion_percent_cep_residents_bolsa_familia,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_10_00,
    idata.transunion_percent_cep_residents_irpf_decl_10_00
  ) AS transunion_percent_cep_residents_irpf_decl_10_00,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_10_01,
    idata.transunion_percent_cep_residents_irpf_decl_10_01
  ) AS transunion_percent_cep_residents_irpf_decl_10_01,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_10_02_04,
    idata.transunion_percent_cep_residents_irpf_decl_10_02_04
  ) AS transunion_percent_cep_residents_irpf_decl_10_02_04,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_10_05_09,
    idata.transunion_percent_cep_residents_irpf_decl_10_05_09
  ) AS transunion_percent_cep_residents_irpf_decl_10_05_09,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_10_10,
    idata.transunion_percent_cep_residents_irpf_decl_10_10
  ) AS transunion_percent_cep_residents_irpf_decl_10_10,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_pend_10_00,
    idata.transunion_percent_cep_residents_irpf_decl_pend_10_00
  ) AS transunion_percent_cep_residents_irpf_decl_pend_10_00,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_pend_10_01,
    idata.transunion_percent_cep_residents_irpf_decl_pend_10_01
  ) AS transunion_percent_cep_residents_irpf_decl_pend_10_01,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_pend_10_02_04,
    idata.transunion_percent_cep_residents_irpf_decl_pend_10_02_04
  ) AS transunion_percent_cep_residents_irpf_decl_pend_10_02_04,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_pend_10_05_09,
    idata.transunion_percent_cep_residents_irpf_decl_pend_10_05_09
  ) AS transunion_percent_cep_residents_irpf_decl_pend_10_05_09,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_pend_10_10,
    idata.transunion_percent_cep_residents_irpf_decl_pend_10_10
  ) AS transunion_percent_cep_residents_irpf_decl_pend_10_10,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_rest_10_00,
    idata.transunion_percent_cep_residents_irpf_decl_rest_10_00
  ) AS transunion_percent_cep_residents_irpf_decl_rest_10_00,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_rest_10_01,
    idata.transunion_percent_cep_residents_irpf_decl_rest_10_01
  ) AS transunion_percent_cep_residents_irpf_decl_rest_10_01,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_rest_10_02_04,
    idata.transunion_percent_cep_residents_irpf_decl_rest_10_02_04
  ) AS transunion_percent_cep_residents_irpf_decl_rest_10_02_04,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_rest_10_05_09,
    idata.transunion_percent_cep_residents_irpf_decl_rest_10_05_09
  ) AS transunion_percent_cep_residents_irpf_decl_rest_10_05_09,
  COALESCE(
    btest.transunion_percent_cep_residents_irpf_decl_rest_10_10,
    idata.transunion_percent_cep_residents_irpf_decl_rest_10_10
  ) AS transunion_percent_cep_residents_irpf_decl_rest_10_10,
  COALESCE(
    btest.transunion_percent_cep_residents_escol_00,
    idata.transunion_percent_cep_residents_escol_00
  ) AS transunion_percent_cep_residents_escol_00,
  COALESCE(
    btest.transunion_percent_cep_residents_escol_01,
    idata.transunion_percent_cep_residents_escol_01
  ) AS transunion_percent_cep_residents_escol_01,
  COALESCE(
    btest.transunion_percent_cep_residents_escol_02,
    idata.transunion_percent_cep_residents_escol_02
  ) AS transunion_percent_cep_residents_escol_02,
  COALESCE(
    btest.transunion_percent_cep_residents_escol_03,
    idata.transunion_percent_cep_residents_escol_03
  ) AS transunion_percent_cep_residents_escol_03,
  COALESCE(
    btest.transunion_percent_cep_residents_escol_04,
    idata.transunion_percent_cep_residents_escol_04
  ) AS transunion_percent_cep_residents_escol_04,
  COALESCE(
    btest.transunion_percent_cep_residents_escol_05,
    idata.transunion_percent_cep_residents_escol_05
  ) AS transunion_percent_cep_residents_escol_05,
  COALESCE(
    btest.transunion_percent_cep_residents_escol_06,
    idata.transunion_percent_cep_residents_escol_06
  ) AS transunion_percent_cep_residents_escol_06,
  COALESCE(
    btest.transunion_percent_cep_residents_escol_07,
    idata.transunion_percent_cep_residents_escol_07
  ) AS transunion_percent_cep_residents_escol_07,
  COALESCE(
    btest.transunion_percent_cep_residents_escol_08,
    idata.transunion_percent_cep_residents_escol_08
  ) AS transunion_percent_cep_residents_escol_08,
  COALESCE(
    btest.transunion_percent_cep_residents_escol_09,
    idata.transunion_percent_cep_residents_escol_09
  ) AS transunion_percent_cep_residents_escol_09,
  COALESCE(
    btest.transunion_percent_cep_residents_escol_10,
    idata.transunion_percent_cep_residents_escol_10
  ) AS transunion_percent_cep_residents_escol_10,
  COALESCE(
    btest.transunion_percent_cep_residents_public_employee,
    idata.transunion_percent_cep_residents_public_employee
  ) AS transunion_percent_cep_residents_public_employee,
  COALESCE(
    btest.transunion_percent_cep_residents_registration_rules_00,
    idata.transunion_percent_cep_residents_registration_rules_00
  ) AS transunion_percent_cep_residents_registration_rules_00,
  COALESCE(
    btest.transunion_percent_cep_residents_registration_rules_01,
    idata.transunion_percent_cep_residents_registration_rules_01
  ) AS transunion_percent_cep_residents_registration_rules_01,
  COALESCE(
    btest.transunion_percent_cep_residents_registration_rules_02,
    idata.transunion_percent_cep_residents_registration_rules_02
  ) AS transunion_percent_cep_residents_registration_rules_02,
  COALESCE(
    btest.transunion_percent_cep_residents_registration_rules_03,
    idata.transunion_percent_cep_residents_registration_rules_03
  ) AS transunion_percent_cep_residents_registration_rules_03,
  COALESCE(
    btest.transunion_percent_cep_residents_registration_rules_04,
    idata.transunion_percent_cep_residents_registration_rules_04
  ) AS transunion_percent_cep_residents_registration_rules_04,
  COALESCE(
    btest.transunion_percent_urban_population_munic,
    idata.transunion_percent_urban_population_munic
  ) AS transunion_percent_urban_population_munic,
  COALESCE(
    btest.transunion_percent_cep_residents_presumed_income_01,
    idata.transunion_percent_cep_residents_presumed_income_01
  ) AS transunion_percent_cep_residents_presumed_income_01,
  COALESCE(
    btest.transunion_percent_cep_residents_presumed_income_02,
    idata.transunion_percent_cep_residents_presumed_income_02
  ) AS transunion_percent_cep_residents_presumed_income_02,
  COALESCE(
    btest.transunion_percent_cep_residents_presumed_income_03,
    idata.transunion_percent_cep_residents_presumed_income_03
  ) AS transunion_percent_cep_residents_presumed_income_03,
  COALESCE(
    btest.transunion_percent_cep_residents_presumed_income_04,
    idata.transunion_percent_cep_residents_presumed_income_04
  ) AS transunion_percent_cep_residents_presumed_income_04,
  COALESCE(
    btest.transunion_percent_cep_residents_presumed_income_05,
    idata.transunion_percent_cep_residents_presumed_income_05
  ) AS transunion_percent_cep_residents_presumed_income_05,
  COALESCE(
    btest.transunion_percent_cep_residents_presumed_income_06,
    idata.transunion_percent_cep_residents_presumed_income_06
  ) AS transunion_percent_cep_residents_presumed_income_06,
  COALESCE(
    btest.transunion_percent_cep_residents_presumed_income_07,
    idata.transunion_percent_cep_residents_presumed_income_07
  ) AS transunion_percent_cep_residents_presumed_income_07,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_high,
    idata.transunion_percent_cep_residents_seg_high
  ) AS transunion_percent_cep_residents_seg_high,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_low,
    idata.transunion_percent_cep_residents_seg_low
  ) AS transunion_percent_cep_residents_seg_low,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_mid,
    idata.transunion_percent_cep_residents_seg_mid
  ) AS transunion_percent_cep_residents_seg_mid,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_charge_high,
    idata.transunion_percent_cep_residents_seg_charge_high
  ) AS transunion_percent_cep_residents_seg_charge_high,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_charge_low,
    idata.transunion_percent_cep_residents_seg_charge_low
  ) AS transunion_percent_cep_residents_seg_charge_low,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_charge_mid,
    idata.transunion_percent_cep_residents_seg_charge_mid
  ) AS transunion_percent_cep_residents_seg_charge_mid,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_ecom_high,
    idata.transunion_percent_cep_residents_seg_ecom_high
  ) AS transunion_percent_cep_residents_seg_ecom_high,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_ecom_low,
    idata.transunion_percent_cep_residents_seg_ecom_low
  ) AS transunion_percent_cep_residents_seg_ecom_low,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_ecom_mid,
    idata.transunion_percent_cep_residents_seg_ecom_mid
  ) AS transunion_percent_cep_residents_seg_ecom_mid,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_fin_high,
    idata.transunion_percent_cep_residents_seg_fin_high
  ) AS transunion_percent_cep_residents_seg_fin_high,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_fin_low,
    idata.transunion_percent_cep_residents_seg_fin_low
  ) AS transunion_percent_cep_residents_seg_fin_low,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_fin_mid,
    idata.transunion_percent_cep_residents_seg_fin_mid
  ) AS transunion_percent_cep_residents_seg_fin_mid,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_very_high,
    idata.transunion_percent_cep_residents_seg_very_high
  ) AS transunion_percent_cep_residents_seg_very_high,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_very_low,
    idata.transunion_percent_cep_residents_seg_very_low
  ) AS transunion_percent_cep_residents_seg_very_low,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_tele_high,
    idata.transunion_percent_cep_residents_seg_tele_high
  ) AS transunion_percent_cep_residents_seg_tele_high,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_tele_low,
    idata.transunion_percent_cep_residents_seg_tele_low
  ) AS transunion_percent_cep_residents_seg_tele_low,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_tele_mid,
    idata.transunion_percent_cep_residents_seg_tele_mid
  ) AS transunion_percent_cep_residents_seg_tele_mid,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_tele_very_high,
    idata.transunion_percent_cep_residents_seg_tele_very_high
  ) AS transunion_percent_cep_residents_seg_tele_very_high,
  COALESCE(
    btest.transunion_percent_cep_residents_seg_tele_very_low,
    idata.transunion_percent_cep_residents_seg_tele_very_low
  ) AS transunion_percent_cep_residents_seg_tele_very_low,
  COALESCE(
    btest.transunion_percent_cep_residents_female,
    idata.transunion_percent_cep_residents_female
  ) AS transunion_percent_cep_residents_female,
  COALESCE(
    btest.transunion_percent_cep_residents_male,
    idata.transunion_percent_cep_residents_male
  ) AS transunion_percent_cep_residents_male,
  COALESCE(
    btest.transunion_percap_pib_munic,
    idata.transunion_percap_pib_munic
  ) AS transunion_percap_pib_munic,
  COALESCE(
    btest.transunion_percent_pib_agro_munic,
    idata.transunion_percent_pib_agro_munic
  ) AS transunion_percent_pib_agro_munic,
  COALESCE(
    btest.transunion_percent_pib_ind_munic,
    idata.transunion_percent_pib_ind_munic
  ) AS transunion_percent_pib_ind_munic,
  COALESCE(
    btest.transunion_percent_pib_serv_munic,
    idata.transunion_percent_pib_serv_munic
  ) AS transunion_percent_pib_serv_munic,
  COALESCE(
    btest.transunion_qtd_irpf_decl_10_years,
    idata.transunion_qtd_irpf_decl_10_years
  ) AS transunion_qtd_irpf_decl_10_years,
  COALESCE(
    btest.transunion_qtd_irpf_decl_3_years,
    idata.transunion_qtd_irpf_decl_3_years
  ) AS transunion_qtd_irpf_decl_3_years,
  COALESCE(
    btest.transunion_qtd_irpf_decl_6_years,
    idata.transunion_qtd_irpf_decl_6_years
  ) AS transunion_qtd_irpf_decl_6_years,
  COALESCE(
    btest.transunion_qtd_irpf_decl_isento,
    idata.transunion_qtd_irpf_decl_isento
  ) AS transunion_qtd_irpf_decl_isento,
  COALESCE(
    btest.transunion_qtd_irpf_decl_pend_10_years,
    idata.transunion_qtd_irpf_decl_pend_10_years
  ) AS transunion_qtd_irpf_decl_pend_10_years,
  COALESCE(
    btest.transunion_qtd_irpf_decl_pend_3_years,
    idata.transunion_qtd_irpf_decl_pend_3_years
  ) AS transunion_qtd_irpf_decl_pend_3_years,
  COALESCE(
    btest.transunion_qtd_irpf_decl_pend_6_years,
    idata.transunion_qtd_irpf_decl_pend_6_years
  ) AS transunion_qtd_irpf_decl_pend_6_years,
  COALESCE(
    btest.transunion_qtd_irpf_decl_rest_10_years,
    idata.transunion_qtd_irpf_decl_rest_10_years
  ) AS transunion_qtd_irpf_decl_rest_10_years,
  COALESCE(
    btest.transunion_qtd_irpf_decl_rest_3_years,
    idata.transunion_qtd_irpf_decl_rest_3_years
  ) AS transunion_qtd_irpf_decl_rest_3_years,
  COALESCE(
    btest.transunion_qtd_irpf_decl_rest_6_years,
    idata.transunion_qtd_irpf_decl_rest_6_years
  ) AS transunion_qtd_irpf_decl_rest_6_years,
  COALESCE(
    btest.transunion_qtd_doc_distinct_emails,
    idata.transunion_qtd_doc_distinct_emails
  ) AS transunion_qtd_doc_distinct_emails,
  COALESCE(
    btest.transunion_qtd_doc_distinct_addresses,
    idata.transunion_qtd_doc_distinct_addresses
  ) AS transunion_qtd_doc_distinct_addresses,
  COALESCE(
    btest.transunion_qtd_household_index_job_stability,
    idata.transunion_qtd_household_index_job_stability
  ) AS transunion_qtd_household_index_job_stability,
  COALESCE(
    btest.transunion_qtd_household_persons,
    idata.transunion_qtd_household_persons
  ) AS transunion_qtd_household_persons,
  COALESCE(
    btest.transunion_qtd_doc_distinct_tel_cel,
    idata.transunion_qtd_doc_distinct_tel_cel
  ) AS transunion_qtd_doc_distinct_tel_cel,
  COALESCE(
    btest.transunion_qtd_doc_distinct_tel_fixo,
    idata.transunion_qtd_doc_distinct_tel_fixo
  ) AS transunion_qtd_doc_distinct_tel_fixo,
  COALESCE(
    btest.transunion_avg_sc_age,
    idata.transunion_avg_sc_age
  ) AS transunion_avg_sc_age,
  COALESCE(
    btest.transunion_avg_sc_resident,
    idata.transunion_avg_sc_resident
  ) AS transunion_avg_sc_resident,
  COALESCE(
    btest.transunion_avg_sc_presumed_income,
    idata.transunion_avg_sc_presumed_income
  ) AS transunion_avg_sc_presumed_income,
  COALESCE(
    btest.transunion_percent_sc_00_17_years,
    idata.transunion_percent_sc_00_17_years
  ) AS transunion_percent_sc_00_17_years,
  COALESCE(
    btest.transunion_percent_sc_18_29_years,
    idata.transunion_percent_sc_18_29_years
  ) AS transunion_percent_sc_18_29_years,
  COALESCE(
    btest.transunion_percent_sc_30_39_years,
    idata.transunion_percent_sc_30_39_years
  ) AS transunion_percent_sc_30_39_years,
  COALESCE(
    btest.transunion_percent_sc_40_49_years,
    idata.transunion_percent_sc_40_49_years
  ) AS transunion_percent_sc_40_49_years,
  COALESCE(
    btest.transunion_percent_sc_50_59_years,
    idata.transunion_percent_sc_50_59_years
  ) AS transunion_percent_sc_50_59_years,
  COALESCE(
    btest.transunion_percent_sc_60_69_years,
    idata.transunion_percent_sc_60_69_years
  ) AS transunion_percent_sc_60_69_years,
  COALESCE(
    btest.transunion_percent_sc_70_95_years,
    idata.transunion_percent_sc_70_95_years
  ) AS transunion_percent_sc_70_95_years,
  COALESCE(
    btest.transunion_percent_sc_bolsa_familia,
    idata.transunion_percent_sc_bolsa_familia
  ) AS transunion_percent_sc_bolsa_familia,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_00,
    idata.transunion_percent_sc_consultas_12_00
  ) AS transunion_percent_sc_consultas_12_00,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_01,
    idata.transunion_percent_sc_consultas_12_01
  ) AS transunion_percent_sc_consultas_12_01,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_02,
    idata.transunion_percent_sc_consultas_12_02
  ) AS transunion_percent_sc_consultas_12_02,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_03,
    idata.transunion_percent_sc_consultas_12_03
  ) AS transunion_percent_sc_consultas_12_03,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_04,
    idata.transunion_percent_sc_consultas_12_04
  ) AS transunion_percent_sc_consultas_12_04,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_charge_00,
    idata.transunion_percent_sc_consultas_12_charge_00
  ) AS transunion_percent_sc_consultas_12_charge_00,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_charge_01,
    idata.transunion_percent_sc_consultas_12_charge_01
  ) AS transunion_percent_sc_consultas_12_charge_01,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_charge_02,
    idata.transunion_percent_sc_consultas_12_charge_02
  ) AS transunion_percent_sc_consultas_12_charge_02,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_ecom_00,
    idata.transunion_percent_sc_consultas_12_ecom_00
  ) AS transunion_percent_sc_consultas_12_ecom_00,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_ecom_01,
    idata.transunion_percent_sc_consultas_12_ecom_01
  ) AS transunion_percent_sc_consultas_12_ecom_01,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_ecom_02,
    idata.transunion_percent_sc_consultas_12_ecom_02
  ) AS transunion_percent_sc_consultas_12_ecom_02,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_fin_00,
    idata.transunion_percent_sc_consultas_12_fin_00
  ) AS transunion_percent_sc_consultas_12_fin_00,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_fin_01,
    idata.transunion_percent_sc_consultas_12_fin_01
  ) AS transunion_percent_sc_consultas_12_fin_01,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_fin_02,
    idata.transunion_percent_sc_consultas_12_fin_02
  ) AS transunion_percent_sc_consultas_12_fin_02,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_tele_00,
    idata.transunion_percent_sc_consultas_12_tele_00
  ) AS transunion_percent_sc_consultas_12_tele_00,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_tele_01,
    idata.transunion_percent_sc_consultas_12_tele_01
  ) AS transunion_percent_sc_consultas_12_tele_01,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_tele_02,
    idata.transunion_percent_sc_consultas_12_tele_02
  ) AS transunion_percent_sc_consultas_12_tele_02,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_tele_03,
    idata.transunion_percent_sc_consultas_12_tele_03
  ) AS transunion_percent_sc_consultas_12_tele_03,
  COALESCE(
    btest.transunion_percent_sc_consultas_12_tele_04,
    idata.transunion_percent_sc_consultas_12_tele_04
  ) AS transunion_percent_sc_consultas_12_tele_04,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_10_00,
    idata.transunion_percent_sc_irpf_decl_10_00
  ) AS transunion_percent_sc_irpf_decl_10_00,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_10_01,
    idata.transunion_percent_sc_irpf_decl_10_01
  ) AS transunion_percent_sc_irpf_decl_10_01,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_10_02,
    idata.transunion_percent_sc_irpf_decl_10_02
  ) AS transunion_percent_sc_irpf_decl_10_02,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_10_03,
    idata.transunion_percent_sc_irpf_decl_10_03
  ) AS transunion_percent_sc_irpf_decl_10_03,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_10_04,
    idata.transunion_percent_sc_irpf_decl_10_04
  ) AS transunion_percent_sc_irpf_decl_10_04,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_pend_10_00,
    idata.transunion_percent_sc_irpf_decl_pend_10_00
  ) AS transunion_percent_sc_irpf_decl_pend_10_00,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_pend_10_01,
    idata.transunion_percent_sc_irpf_decl_pend_10_01
  ) AS transunion_percent_sc_irpf_decl_pend_10_01,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_pend_10_02,
    idata.transunion_percent_sc_irpf_decl_pend_10_02
  ) AS transunion_percent_sc_irpf_decl_pend_10_02,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_pend_10_03,
    idata.transunion_percent_sc_irpf_decl_pend_10_03
  ) AS transunion_percent_sc_irpf_decl_pend_10_03,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_pend_10_04,
    idata.transunion_percent_sc_irpf_decl_pend_10_04
  ) AS transunion_percent_sc_irpf_decl_pend_10_04,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_rest_10_00,
    idata.transunion_percent_sc_irpf_decl_rest_10_00
  ) AS transunion_percent_sc_irpf_decl_rest_10_00,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_rest_10_01,
    idata.transunion_percent_sc_irpf_decl_rest_10_01
  ) AS transunion_percent_sc_irpf_decl_rest_10_01,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_rest_10_02,
    idata.transunion_percent_sc_irpf_decl_rest_10_02
  ) AS transunion_percent_sc_irpf_decl_rest_10_02,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_rest_10_03,
    idata.transunion_percent_sc_irpf_decl_rest_10_03
  ) AS transunion_percent_sc_irpf_decl_rest_10_03,
  COALESCE(
    btest.transunion_percent_sc_irpf_decl_rest_10_04,
    idata.transunion_percent_sc_irpf_decl_rest_10_04
  ) AS transunion_percent_sc_irpf_decl_rest_10_04,
  COALESCE(
    btest.transunion_percent_sc_residence_1_bathroom,
    idata.transunion_percent_sc_residence_1_bathroom
  ) AS transunion_percent_sc_residence_1_bathroom,
  COALESCE(
    btest.transunion_percent_sc_residence_1_resident,
    idata.transunion_percent_sc_residence_1_resident
  ) AS transunion_percent_sc_residence_1_resident,
  COALESCE(
    btest.transunion_percent_sc_residence_2_bathrooms,
    idata.transunion_percent_sc_residence_2_bathrooms
  ) AS transunion_percent_sc_residence_2_bathrooms,
  COALESCE(
    btest.transunion_percent_sc_residence_2_residents,
    idata.transunion_percent_sc_residence_2_residents
  ) AS transunion_percent_sc_residence_2_residents,
  COALESCE(
    btest.transunion_percent_sc_residence_3_residents,
    idata.transunion_percent_sc_residence_3_residents
  ) AS transunion_percent_sc_residence_3_residents,
  COALESCE(
    btest.transunion_percent_sc_residence_4_residents,
    idata.transunion_percent_sc_residence_4_residents
  ) AS transunion_percent_sc_residence_4_residents,
  COALESCE(
    btest.transunion_percent_sc_residence_other_ways,
    idata.transunion_percent_sc_residence_other_ways
  ) AS transunion_percent_sc_residence_other_ways,
  COALESCE(
    btest.transunion_percent_sc_residence_water_supply,
    idata.transunion_percent_sc_residence_water_supply
  ) AS transunion_percent_sc_residence_water_supply,
  COALESCE(
    btest.transunion_percent_sc_residence_rent,
    idata.transunion_percent_sc_residence_rent
  ) AS transunion_percent_sc_residence_rent,
  COALESCE(
    btest.transunion_percent_sc_residence_apartments,
    idata.transunion_percent_sc_residence_apartments
  ) AS transunion_percent_sc_residence_apartments,
  COALESCE(
    btest.transunion_percent_sc_residence_exclusive_bathroom,
    idata.transunion_percent_sc_residence_exclusive_bathroom
  ) AS transunion_percent_sc_residence_exclusive_bathroom,
  COALESCE(
    btest.transunion_percent_sc_residence_houses,
    idata.transunion_percent_sc_residence_houses
  ) AS transunion_percent_sc_residence_houses,
  COALESCE(
    btest.transunion_percent_sc_residence_condo_houses,
    idata.transunion_percent_sc_residence_condo_houses
  ) AS transunion_percent_sc_residence_condo_houses,
  COALESCE(
    btest.transunion_percent_sc_residence_garbage_collection,
    idata.transunion_percent_sc_residence_garbage_collection
  ) AS transunion_percent_sc_residence_garbage_collection,
  COALESCE(
    btest.transunion_percent_sc_residence_garbage_collection_cacamba,
    idata.transunion_percent_sc_residence_garbage_collection_cacamba
  ) AS transunion_percent_sc_residence_garbage_collection_cacamba,
  COALESCE(
    btest.transunion_percent_sc_residence_garbage_collection_other_ways,
    idata.transunion_percent_sc_residence_garbage_collection_other_ways
  ) AS transunion_percent_sc_residence_garbage_collection_other_ways,
  COALESCE(
    btest.transunion_percent_sc_residence_garbage_collection_cleanup_service,
    idata.transunion_percent_sc_residence_garbage_collection_cleanup_service
  ) AS transunion_percent_sc_residence_garbage_collection_cleanup_service,
  COALESCE(
    btest.transunion_percent_sc_residence_open_sewer,
    idata.transunion_percent_sc_residence_open_sewer
  ) AS transunion_percent_sc_residence_open_sewer,
  COALESCE(
    btest.transunion_percent_sc_residence_accumulated_garbage,
    idata.transunion_percent_sc_residence_accumulated_garbage
  ) AS transunion_percent_sc_residence_accumulated_garbage,
  COALESCE(
    btest.transunion_percent_sc_residence_in_acquiring,
    idata.transunion_percent_sc_residence_in_acquiring
  ) AS transunion_percent_sc_residence_in_acquiring,
  COALESCE(
    btest.transunion_percent_sc_residence_electrical_supply,
    idata.transunion_percent_sc_residence_electrical_supply
  ) AS transunion_percent_sc_residence_electrical_supply,
  COALESCE(
    btest.transunion_percent_sc_residence_energy_meter_shared,
    idata.transunion_percent_sc_residence_energy_meter_shared
  ) AS transunion_percent_sc_residence_energy_meter_shared,
  COALESCE(
    btest.transunion_percent_sc_residence_energy_meter_exclusive,
    idata.transunion_percent_sc_residence_energy_meter_exclusive
  ) AS transunion_percent_sc_residence_energy_meter_exclusive,
  COALESCE(
    btest.transunion_percent_sc_residence_energy_meter_other_ways,
    idata.transunion_percent_sc_residence_energy_meter_other_ways
  ) AS transunion_percent_sc_residence_energy_meter_other_ways,
  COALESCE(
    btest.transunion_percent_sc_residence_power_distribution_network,
    idata.transunion_percent_sc_residence_power_distribution_network
  ) AS transunion_percent_sc_residence_power_distribution_network,
  COALESCE(
    btest.transunion_percent_sc_residence_energy_meter_without,
    idata.transunion_percent_sc_residence_energy_meter_without
  ) AS transunion_percent_sc_residence_energy_meter_without,
  COALESCE(
    btest.transunion_percent_sc_residence_sewage_too_much,
    idata.transunion_percent_sc_residence_sewage_too_much
  ) AS transunion_percent_sc_residence_sewage_too_much,
  COALESCE(
    btest.transunion_percent_sc_residence_sewage_septic_tank,
    idata.transunion_percent_sc_residence_sewage_septic_tank
  ) AS transunion_percent_sc_residence_sewage_septic_tank,
  COALESCE(
    btest.transunion_percent_sc_residence_sewage_public_network,
    idata.transunion_percent_sc_residence_sewage_public_network
  ) AS transunion_percent_sc_residence_sewage_public_network,
  COALESCE(
    btest.transunion_percent_sc_residence_gt_2_bathrooms,
    idata.transunion_percent_sc_residence_gt_2_bathrooms
  ) AS transunion_percent_sc_residence_gt_2_bathrooms,
  COALESCE(
    btest.transunion_percent_sc_residence_gt_4_residents,
    idata.transunion_percent_sc_residence_gt_4_residents
  ) AS transunion_percent_sc_residence_gt_4_residents,
  COALESCE(
    btest.transunion_percent_sc_residence_adequate_housing,
    idata.transunion_percent_sc_residence_adequate_housing
  ) AS transunion_percent_sc_residence_adequate_housing,
  COALESCE(
    btest.transunion_percent_sc_residence_inadequate_housing,
    idata.transunion_percent_sc_residence_inadequate_housing
  ) AS transunion_percent_sc_residence_inadequate_housing,
  COALESCE(
    btest.transunion_percent_sc_residence_semi_adequate_housing,
    idata.transunion_percent_sc_residence_semi_adequate_housing
  ) AS transunion_percent_sc_residence_semi_adequate_housing,
  COALESCE(
    btest.transunion_percent_sc_residence_permanent_residents,
    idata.transunion_percent_sc_residence_permanent_residents
  ) AS transunion_percent_sc_residence_permanent_residents,
  COALESCE(
    btest.transunion_percent_sc_residence_paid_off,
    idata.transunion_percent_sc_residence_paid_off
  ) AS transunion_percent_sc_residence_paid_off,
  COALESCE(
    btest.transunion_percent_sc_residence_monthly_income_gt_10sm,
    idata.transunion_percent_sc_residence_monthly_income_gt_10sm
  ) AS transunion_percent_sc_residence_monthly_income_gt_10sm,
  COALESCE(
    btest.transunion_percent_sc_residence_monthly_income_until_1s8_sm,
    idata.transunion_percent_sc_residence_monthly_income_until_1s8_sm
  ) AS transunion_percent_sc_residence_monthly_income_until_1s8_sm,
  COALESCE(
    btest.transunion_percent_sc_residence_monthly_income_1_a_2_sm,
    idata.transunion_percent_sc_residence_monthly_income_1_a_2_sm
  ) AS transunion_percent_sc_residence_monthly_income_1_a_2_sm,
  COALESCE(
    btest.transunion_percent_sc_residence_monthly_income_1s2_a_1_sm,
    idata.transunion_percent_sc_residence_monthly_income_1s2_a_1_sm
  ) AS transunion_percent_sc_residence_monthly_income_1s2_a_1_sm,
  COALESCE(
    btest.transunion_percent_sc_residence_monthly_income_1s4_a_1s2_sm,
    idata.transunion_percent_sc_residence_monthly_income_1s4_a_1s2_sm
  ) AS transunion_percent_sc_residence_monthly_income_1s4_a_1s2_sm,
  COALESCE(
    btest.transunion_percent_sc_residence_monthly_income_1s8_a_1s4_sm,
    idata.transunion_percent_sc_residence_monthly_income_1s8_a_1s4_sm
  ) AS transunion_percent_sc_residence_monthly_income_1s8_a_1s4_sm,
  COALESCE(
    btest.transunion_percent_sc_residence_monthly_income_2_a_3_sm,
    idata.transunion_percent_sc_residence_monthly_income_2_a_3_sm
  ) AS transunion_percent_sc_residence_monthly_income_2_a_3_sm,
  COALESCE(
    btest.transunion_percent_sc_residence_monthly_income_3_a_5_sm,
    idata.transunion_percent_sc_residence_monthly_income_3_a_5_sm
  ) AS transunion_percent_sc_residence_monthly_income_3_a_5_sm,
  COALESCE(
    btest.transunion_percent_sc_residence_monthly_income_5_a_10_sm,
    idata.transunion_percent_sc_residence_monthly_income_5_a_10_sm
  ) AS transunion_percent_sc_residence_monthly_income_5_a_10_sm,
  COALESCE(
    btest.transunion_percent_sc_residence_afforestation_without,
    idata.transunion_percent_sc_residence_afforestation_without
  ) AS transunion_percent_sc_residence_afforestation_without,
  COALESCE(
    btest.transunion_percent_sc_residence_manhole_without,
    idata.transunion_percent_sc_residence_manhole_without
  ) AS transunion_percent_sc_residence_manhole_without,
  COALESCE(
    btest.transunion_percent_sc_residence_sidewalk_without,
    idata.transunion_percent_sc_residence_sidewalk_without
  ) AS transunion_percent_sc_residence_sidewalk_without,
  COALESCE(
    btest.transunion_percent_sc_residence_curb_without,
    idata.transunion_percent_sc_residence_curb_without
  ) AS transunion_percent_sc_residence_curb_without,
  COALESCE(
    btest.transunion_percent_sc_residence_public_place_without,
    idata.transunion_percent_sc_residence_public_place_without
  ) AS transunion_percent_sc_residence_public_place_without,
  COALESCE(
    btest.transunion_percent_sc_residence_public_energy_without,
    idata.transunion_percent_sc_residence_public_energy_without
  ) AS transunion_percent_sc_residence_public_energy_without,
  COALESCE(
    btest.transunion_percent_sc_residence_female_resident_without,
    idata.transunion_percent_sc_residence_female_resident_without
  ) AS transunion_percent_sc_residence_female_resident_without,
  COALESCE(
    btest.transunion_percent_sc_residence_male_resident_without,
    idata.transunion_percent_sc_residence_male_resident_without
  ) AS transunion_percent_sc_residence_male_resident_without,
  COALESCE(
    btest.transunion_percent_sc_residence_paving_without,
    idata.transunion_percent_sc_residence_paving_without
  ) AS transunion_percent_sc_residence_paving_without,
  COALESCE(
    btest.transunion_percent_sc_residence_accessibility_ramp_without,
    idata.transunion_percent_sc_residence_accessibility_ramp_without
  ) AS transunion_percent_sc_residence_accessibility_ramp_without,
  COALESCE(
    btest.transunion_percent_sc_residence_monthly_income_without,
    idata.transunion_percent_sc_residence_monthly_income_without
  ) AS transunion_percent_sc_residence_monthly_income_without,
  COALESCE(
    btest.transunion_percent_sc_escol_00,
    idata.transunion_percent_sc_escol_00
  ) AS transunion_percent_sc_escol_00,
  COALESCE(
    btest.transunion_percent_sc_escol_01,
    idata.transunion_percent_sc_escol_01
  ) AS transunion_percent_sc_escol_01,
  COALESCE(
    btest.transunion_percent_sc_escol_02,
    idata.transunion_percent_sc_escol_02
  ) AS transunion_percent_sc_escol_02,
  COALESCE(
    btest.transunion_percent_sc_escol_03,
    idata.transunion_percent_sc_escol_03
  ) AS transunion_percent_sc_escol_03,
  COALESCE(
    btest.transunion_percent_sc_escol_04,
    idata.transunion_percent_sc_escol_04
  ) AS transunion_percent_sc_escol_04,
  COALESCE(
    btest.transunion_percent_sc_escol_05,
    idata.transunion_percent_sc_escol_05
  ) AS transunion_percent_sc_escol_05,
  COALESCE(
    btest.transunion_percent_sc_escol_06,
    idata.transunion_percent_sc_escol_06
  ) AS transunion_percent_sc_escol_06,
  COALESCE(
    btest.transunion_percent_sc_escol_07,
    idata.transunion_percent_sc_escol_07
  ) AS transunion_percent_sc_escol_07,
  COALESCE(
    btest.transunion_percent_sc_escol_08,
    idata.transunion_percent_sc_escol_08
  ) AS transunion_percent_sc_escol_08,
  COALESCE(
    btest.transunion_percent_sc_escol_09,
    idata.transunion_percent_sc_escol_09
  ) AS transunion_percent_sc_escol_09,
  COALESCE(
    btest.transunion_percent_sc_escol_10,
    idata.transunion_percent_sc_escol_10
  ) AS transunion_percent_sc_escol_10,
  COALESCE(
    btest.transunion_percent_sc_public_employee,
    idata.transunion_percent_sc_public_employee
  ) AS transunion_percent_sc_public_employee,
  COALESCE(
    btest.transunion_percent_sc_resident_water_supply,
    idata.transunion_percent_sc_resident_water_supply
  ) AS transunion_percent_sc_resident_water_supply,
  COALESCE(
    btest.transunion_percent_sc_resident_apartment,
    idata.transunion_percent_sc_resident_apartment
  ) AS transunion_percent_sc_resident_apartment,
  COALESCE(
    btest.transunion_percent_sc_resident_house,
    idata.transunion_percent_sc_resident_house
  ) AS transunion_percent_sc_resident_house,
  COALESCE(
    btest.transunion_percent_sc_resident_condo_house,
    idata.transunion_percent_sc_resident_condo_house
  ) AS transunion_percent_sc_resident_condo_house,
  COALESCE(
    btest.transunion_percent_sc_resident_garbage_collection,
    idata.transunion_percent_sc_resident_garbage_collection
  ) AS transunion_percent_sc_resident_garbage_collection,
  COALESCE(
    btest.transunion_percent_sc_resident_gargabe_collection_service,
    idata.transunion_percent_sc_resident_gargabe_collection_service
  ) AS transunion_percent_sc_resident_gargabe_collection_service,
  COALESCE(
    btest.transunion_percent_sc_resident_residence_acquired_other_ways,
    idata.transunion_percent_sc_resident_residence_acquired_other_ways
  ) AS transunion_percent_sc_resident_residence_acquired_other_ways,
  COALESCE(
    btest.transunion_percent_sc_resident_residence_rent,
    idata.transunion_percent_sc_resident_residence_rent
  ) AS transunion_percent_sc_resident_residence_rent,
  COALESCE(
    btest.transunion_percent_sc_resident_residence_in_acquisition,
    idata.transunion_percent_sc_resident_residence_in_acquisition
  ) AS transunion_percent_sc_resident_residence_in_acquisition,
  COALESCE(
    btest.transunion_percent_sc_resident_residence_permanent,
    idata.transunion_percent_sc_resident_residence_permanent
  ) AS transunion_percent_sc_resident_residence_permanent,
  COALESCE(
    btest.transunion_percent_sc_resident_residence_paid_off,
    idata.transunion_percent_sc_resident_residence_paid_off
  ) AS transunion_percent_sc_resident_residence_paid_off,
  COALESCE(
    btest.transunion_percent_sc_resident_residence_electrical_supply,
    idata.transunion_percent_sc_resident_residence_electrical_supply
  ) AS transunion_percent_sc_resident_residence_electrical_supply,
  COALESCE(
    btest.transunion_percent_people_0_4_years,
    idata.transunion_percent_people_0_4_years
  ) AS transunion_percent_people_0_4_years,
  COALESCE(
    btest.transunion_percent_people_10_14_years,
    idata.transunion_percent_people_10_14_years
  ) AS transunion_percent_people_10_14_years,
  COALESCE(
    btest.transunion_percent_people_15_17_years,
    idata.transunion_percent_people_15_17_years
  ) AS transunion_percent_people_15_17_years,
  COALESCE(
    btest.transunion_percent_people_18_19_years,
    idata.transunion_percent_people_18_19_years
  ) AS transunion_percent_people_18_19_years,
  COALESCE(
    btest.transunion_percent_people_20_24_years,
    idata.transunion_percent_people_20_24_years
  ) AS transunion_percent_people_20_24_years,
  COALESCE(
    btest.transunion_percent_people_25_29_years,
    idata.transunion_percent_people_25_29_years
  ) AS transunion_percent_people_25_29_years,
  COALESCE(
    btest.transunion_percent_people_30_34_years,
    idata.transunion_percent_people_30_34_years
  ) AS transunion_percent_people_30_34_years,
  COALESCE(
    btest.transunion_percent_people_35_39_years,
    idata.transunion_percent_people_35_39_years
  ) AS transunion_percent_people_35_39_years,
  COALESCE(
    btest.transunion_percent_people_40_44_years,
    idata.transunion_percent_people_40_44_years
  ) AS transunion_percent_people_40_44_years,
  COALESCE(
    btest.transunion_percent_people_45_49_years,
    idata.transunion_percent_people_45_49_years
  ) AS transunion_percent_people_45_49_years,
  COALESCE(
    btest.transunion_percent_people_50_54_years,
    idata.transunion_percent_people_50_54_years
  ) AS transunion_percent_people_50_54_years,
  COALESCE(
    btest.transunion_percent_people_55_59_years,
    idata.transunion_percent_people_55_59_years
  ) AS transunion_percent_people_55_59_years,
  COALESCE(
    btest.transunion_percent_people_5_9_years,
    idata.transunion_percent_people_5_9_years
  ) AS transunion_percent_people_5_9_years,
  COALESCE(
    btest.transunion_percent_people_60_69_years,
    idata.transunion_percent_people_60_69_years
  ) AS transunion_percent_people_60_69_years,
  COALESCE(
    btest.transunion_percent_people_registration_birth,
    idata.transunion_percent_people_registration_birth
  ) AS transunion_percent_people_registration_birth,
  COALESCE(
    btest.transunion_percent_people_gt_69_years,
    idata.transunion_percent_people_gt_69_years
  ) AS transunion_percent_people_gt_69_years,
  COALESCE(
    btest.transunion_percent_people_registration_birth_not_known,
    idata.transunion_percent_people_registration_birth_not_known
  ) AS transunion_percent_people_registration_birth_not_known,
  COALESCE(
    btest.transunion_percent_people_monthly_income_10_a_15_sm,
    idata.transunion_percent_people_monthly_income_10_a_15_sm
  ) AS transunion_percent_people_monthly_income_10_a_15_sm,
  COALESCE(
    btest.transunion_percent_people_monthly_income_15_a_20_sm,
    idata.transunion_percent_people_monthly_income_15_a_20_sm
  ) AS transunion_percent_people_monthly_income_15_a_20_sm,
  COALESCE(
    btest.transunion_percent_people_monthly_income_1_a_2_sm,
    idata.transunion_percent_people_monthly_income_1_a_2_sm
  ) AS transunion_percent_people_monthly_income_1_a_2_sm,
  COALESCE(
    btest.transunion_percent_people_monthly_income_1s2_a_1_sm,
    idata.transunion_percent_people_monthly_income_1s2_a_1_sm
  ) AS transunion_percent_people_monthly_income_1s2_a_1_sm,
  COALESCE(
    btest.transunion_percent_people_monthly_income_2_a_3_sm,
    idata.transunion_percent_people_monthly_income_2_a_3_sm
  ) AS transunion_percent_people_monthly_income_2_a_3_sm,
  COALESCE(
    btest.transunion_percent_people_monthly_income_3_a_5_sm,
    idata.transunion_percent_people_monthly_income_3_a_5_sm
  ) AS transunion_percent_people_monthly_income_3_a_5_sm,
  COALESCE(
    btest.transunion_percent_people_monthly_income_5_a_10_sm,
    idata.transunion_percent_people_monthly_income_5_a_10_sm
  ) AS transunion_percent_people_monthly_income_5_a_10_sm,
  COALESCE(
    btest.transunion_percent_people_monthly_income_gt_20_sm,
    idata.transunion_percent_people_monthly_income_gt_20_sm
  ) AS transunion_percent_people_monthly_income_gt_20_sm,
  COALESCE(
    btest.transunion_percent_people_monthly_income_until_1s2_sm,
    idata.transunion_percent_people_monthly_income_until_1s2_sm
  ) AS transunion_percent_people_monthly_income_until_1s2_sm,
  COALESCE(
    btest.transunion_percent_people_registration_birth_without,
    idata.transunion_percent_people_registration_birth_without
  ) AS transunion_percent_people_registration_birth_without,
  COALESCE(
    btest.transunion_percent_people_monthly_income_without,
    idata.transunion_percent_people_monthly_income_without
  ) AS transunion_percent_people_monthly_income_without,
  COALESCE(
    btest.transunion_percent_sc_income_01,
    idata.transunion_percent_sc_income_01
  ) AS transunion_percent_sc_income_01,
  COALESCE(
    btest.transunion_percent_sc_income_02,
    idata.transunion_percent_sc_income_02
  ) AS transunion_percent_sc_income_02,
  COALESCE(
    btest.transunion_percent_sc_income_03,
    idata.transunion_percent_sc_income_03
  ) AS transunion_percent_sc_income_03,
  COALESCE(
    btest.transunion_percent_sc_income_04,
    idata.transunion_percent_sc_income_04
  ) AS transunion_percent_sc_income_04,
  COALESCE(
    btest.transunion_percent_sc_income_05,
    idata.transunion_percent_sc_income_05
  ) AS transunion_percent_sc_income_05,
  COALESCE(
    btest.transunion_percent_sc_income_06,
    idata.transunion_percent_sc_income_06
  ) AS transunion_percent_sc_income_06,
  COALESCE(
    btest.transunion_percent_sc_income_07,
    idata.transunion_percent_sc_income_07
  ) AS transunion_percent_sc_income_07,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_literate_female,
    idata.transunion_percent_sc_responsible_person_literate_female
  ) AS transunion_percent_sc_responsible_person_literate_female,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_literate_male,
    idata.transunion_percent_sc_responsible_person_literate_male
  ) AS transunion_percent_sc_responsible_person_literate_male,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_female,
    idata.transunion_percent_sc_responsible_person_female
  ) AS transunion_percent_sc_responsible_person_female,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_male,
    idata.transunion_percent_sc_responsible_person_male
  ) AS transunion_percent_sc_responsible_person_male,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_monthly_income_10_a_15_sm,
    idata.transunion_percent_sc_responsible_person_monthly_income_10_a_15_sm
  ) AS transunion_percent_sc_responsible_person_monthly_income_10_a_15_sm,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_monthly_income_15_a_20_sm,
    idata.transunion_percent_sc_responsible_person_monthly_income_15_a_20_sm
  ) AS transunion_percent_sc_responsible_person_monthly_income_15_a_20_sm,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_monthly_income_1_a_2_sm,
    idata.transunion_percent_sc_responsible_person_monthly_income_1_a_2_sm
  ) AS transunion_percent_sc_responsible_person_monthly_income_1_a_2_sm,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_monthly_income_1s2_a_1_sm,
    idata.transunion_percent_sc_responsible_person_monthly_income_1s2_a_1_sm
  ) AS transunion_percent_sc_responsible_person_monthly_income_1s2_a_1_sm,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_monthly_income_2_a_3_sm,
    idata.transunion_percent_sc_responsible_person_monthly_income_2_a_3_sm
  ) AS transunion_percent_sc_responsible_person_monthly_income_2_a_3_sm,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_monthly_income_3_a_5_sm,
    idata.transunion_percent_sc_responsible_person_monthly_income_3_a_5_sm
  ) AS transunion_percent_sc_responsible_person_monthly_income_3_a_5_sm,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_monthly_income_5_a_10_sm,
    idata.transunion_percent_sc_responsible_person_monthly_income_5_a_10_sm
  ) AS transunion_percent_sc_responsible_person_monthly_income_5_a_10_sm,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_monthly_income_gt_20_sm,
    idata.transunion_percent_sc_responsible_person_monthly_income_gt_20_sm
  ) AS transunion_percent_sc_responsible_person_monthly_income_gt_20_sm,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_monthly_income_until_1s2_sm,
    idata.transunion_percent_sc_responsible_person_monthly_income_until_1s2_sm
  ) AS transunion_percent_sc_responsible_person_monthly_income_until_1s2_sm,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_monthly_income_without,
    idata.transunion_percent_sc_responsible_person_monthly_income_without
  ) AS transunion_percent_sc_responsible_person_monthly_income_without,
  COALESCE(
    btest.transunion_percent_sc_female,
    idata.transunion_percent_sc_female
  ) AS transunion_percent_sc_female,
  COALESCE(
    btest.transunion_percent_sc_male,
    idata.transunion_percent_sc_male
  ) AS transunion_percent_sc_male,
  COALESCE(
    btest.transunion_percent_sc_qsa,
    idata.transunion_percent_sc_qsa
  ) AS transunion_percent_sc_qsa,
  COALESCE(
    btest.transunion_percent_sc_residence_avg_monthly_income_salario_minimo,
    idata.transunion_percent_sc_residence_avg_monthly_income_salario_minimo
  ) AS transunion_percent_sc_residence_avg_monthly_income_salario_minimo,
  COALESCE(
    btest.transunion_percent_sc_responsible_person_avg_monthly_income_salario_minimo,
    idata.transunion_percent_sc_responsible_person_avg_monthly_income_salario_minimo
  ) AS transunion_percent_sc_responsible_person_avg_monthly_income_salario_minimo,
  COALESCE(
    btest.transunion_sum_sc_persons_monthly_income_gt_10_years,
    idata.transunion_sum_sc_persons_monthly_income_gt_10_years
  ) AS transunion_sum_sc_persons_monthly_income_gt_10_years,
  COALESCE(
    btest.transunion_sum_sc_responsible_persons_monthly_income,
    idata.transunion_sum_sc_responsible_persons_monthly_income
  ) AS transunion_sum_sc_responsible_persons_monthly_income,
  COALESCE(
    btest.transunion_sum_household_presumed_income,
    idata.transunion_sum_household_presumed_income
  ) AS transunion_sum_household_presumed_income,
  COALESCE(
    btest.transunion_time_cpf_emission,
    idata.transunion_time_cpf_emission
  ) AS transunion_time_cpf_emission,
  COALESCE(
    btest.transunion_time_months_last_cel_phone,
    idata.transunion_time_months_last_cel_phone
  ) AS transunion_time_months_last_cel_phone,
  COALESCE(
    btest.transunion_time_months_last_tel_fixo,
    idata.transunion_time_months_last_tel_fixo
  ) AS transunion_time_months_last_tel_fixo,
  COALESCE(
    btest.transunion_time_last_irpf_decl_rest,
    idata.transunion_time_last_irpf_decl_rest
  ) AS transunion_time_last_irpf_decl_rest,
  COALESCE(
    btest.transunion_time_last_irpf_decl,
    idata.transunion_time_last_irpf_decl
  ) AS transunion_time_last_irpf_decl,
  COALESCE(
    btest.transunion_time_last_irpf_decl_pend,
    idata.transunion_time_last_irpf_decl_pend
  ) AS transunion_time_last_irpf_decl_pend,
  COALESCE(
    btest.transunion_has_household_11_15_years,
    idata.transunion_has_household_11_15_years
  ) AS transunion_has_household_11_15_years,
  COALESCE(
    btest.transunion_has_household_16_17_years,
    idata.transunion_has_household_16_17_years
  ) AS transunion_has_household_16_17_years,
  COALESCE(
    btest.transunion_has_household_18_20_years,
    idata.transunion_has_household_18_20_years
  ) AS transunion_has_household_18_20_years,
  COALESCE(
    btest.transunion_has_household_21_25_years,
    idata.transunion_has_household_21_25_years
  ) AS transunion_has_household_21_25_years,
  COALESCE(
    btest.transunion_has_household_25_30_years,
    idata.transunion_has_household_25_30_years
  ) AS transunion_has_household_25_30_years,
  COALESCE(
    btest.transunion_has_household_3_5_years,
    idata.transunion_has_household_3_5_years
  ) AS transunion_has_household_3_5_years,
  COALESCE(
    btest.transunion_has_household_6_10_years,
    idata.transunion_has_household_6_10_years
  ) AS transunion_has_household_6_10_years,
  COALESCE(
    btest.transunion_has_household_until_2_years,
    idata.transunion_has_household_until_2_years
  ) AS transunion_has_household_until_2_years,
  COALESCE(
    btest.transunion_is_public_employee,
    idata.transunion_is_public_employee
  ) AS transunion_is_public_employee,
  COALESCE(
    btest.transunion_is_business_partner,
    idata.transunion_is_business_partner
  ) AS transunion_is_business_partner,
  COALESCE(
    btest.transunion_is_tel_cel_procon,
    idata.transunion_is_tel_cel_procon
  ) AS transunion_is_tel_cel_procon,
  COALESCE(
    btest.transunion_is_tel_fixo_assin,
    idata.transunion_is_tel_fixo_assin
  ) AS transunion_is_tel_fixo_assin,
  COALESCE(
    btest.transunion_is_tel_fixo_procon,
    idata.transunion_is_tel_fixo_procon
  ) AS transunion_is_tel_fixo_procon,
  COALESCE(
    btest.transunion_has_household_bolsa_familia,
    idata.transunion_has_household_bolsa_familia
  ) AS transunion_has_household_bolsa_familia,
  COALESCE(
    btest.transunion_has_household_irpf_decl_10_years,
    idata.transunion_has_household_irpf_decl_10_years
  ) AS transunion_has_household_irpf_decl_10_years,
  COALESCE(
    btest.transunion_has_household_irpf_decl_3_years,
    idata.transunion_has_household_irpf_decl_3_years
  ) AS transunion_has_household_irpf_decl_3_years,
  COALESCE(
    btest.transunion_has_household_irpf_decl_6_years,
    idata.transunion_has_household_irpf_decl_6_years
  ) AS transunion_has_household_irpf_decl_6_years,
  COALESCE(
    btest.transunion_has_household_irpf_decl_pend_10_years,
    idata.transunion_has_household_irpf_decl_pend_10_years
  ) AS transunion_has_household_irpf_decl_pend_10_years,
  COALESCE(
    btest.transunion_has_household_irpf_decl_pend_3_years,
    idata.transunion_has_household_irpf_decl_pend_3_years
  ) AS transunion_has_household_irpf_decl_pend_3_years,
  COALESCE(
    btest.transunion_has_household_irpf_decl_pend_6_years,
    idata.transunion_has_household_irpf_decl_pend_6_years
  ) AS transunion_has_household_irpf_decl_pend_6_years,
  COALESCE(
    btest.transunion_has_household_irpf_decl_rest_10_years,
    idata.transunion_has_household_irpf_decl_rest_10_years
  ) AS transunion_has_household_irpf_decl_rest_10_years,
  COALESCE(
    btest.transunion_has_household_irpf_decl_rest_3_years,
    idata.transunion_has_household_irpf_decl_rest_3_years
  ) AS transunion_has_household_irpf_decl_rest_3_years,
  COALESCE(
    btest.transunion_has_household_irpf_decl_rest_6_years,
    idata.transunion_has_household_irpf_decl_rest_6_years
  ) AS transunion_has_household_irpf_decl_rest_6_years,
  COALESCE(
    btest.transunion_has_household_public_employee,
    idata.transunion_has_household_public_employee
  ) AS transunion_has_household_public_employee,
  COALESCE(
    btest.transunion_has_household_gt_35_years,
    idata.transunion_has_household_gt_35_years
  ) AS transunion_has_household_gt_35_years,
  COALESCE(
    btest.transunion_has_household_index_job_stability,
    idata.transunion_has_household_index_job_stability
  ) AS transunion_has_household_index_job_stability,
  COALESCE(
    btest.transunion_has_household_invalid_registration_rules,
    idata.transunion_has_household_invalid_registration_rules
  ) AS transunion_has_household_invalid_registration_rules,
  COALESCE(
    btest.transunion_has_household_index_charge_1,
    idata.transunion_has_household_index_charge_1
  ) AS transunion_has_household_index_charge_1,
  COALESCE(
    btest.transunion_has_household_index_charge_2,
    idata.transunion_has_household_index_charge_2
  ) AS transunion_has_household_index_charge_2,
  COALESCE(
    btest.transunion_has_household_index_charge_3,
    idata.transunion_has_household_index_charge_3
  ) AS transunion_has_household_index_charge_3,
  COALESCE(
    btest.transunion_has_household_index_charge_4,
    idata.transunion_has_household_index_charge_4
  ) AS transunion_has_household_index_charge_4,
  COALESCE(
    btest.transunion_has_household_index_charge_5,
    idata.transunion_has_household_index_charge_5
  ) AS transunion_has_household_index_charge_5,
  COALESCE(
    btest.transunion_has_household_index_ecom_1,
    idata.transunion_has_household_index_ecom_1
  ) AS transunion_has_household_index_ecom_1,
  COALESCE(
    btest.transunion_has_household_index_ecom_2,
    idata.transunion_has_household_index_ecom_2
  ) AS transunion_has_household_index_ecom_2,
  COALESCE(
    btest.transunion_has_household_index_ecom_3,
    idata.transunion_has_household_index_ecom_3
  ) AS transunion_has_household_index_ecom_3,
  COALESCE(
    btest.transunion_has_household_index_ecom_4,
    idata.transunion_has_household_index_ecom_4
  ) AS transunion_has_household_index_ecom_4,
  COALESCE(
    btest.transunion_has_household_index_ecom_5,
    idata.transunion_has_household_index_ecom_5
  ) AS transunion_has_household_index_ecom_5,
  COALESCE(
    btest.transunion_has_household_index_fin_1,
    idata.transunion_has_household_index_fin_1
  ) AS transunion_has_household_index_fin_1,
  COALESCE(
    btest.transunion_has_household_index_fin_2,
    idata.transunion_has_household_index_fin_2
  ) AS transunion_has_household_index_fin_2,
  COALESCE(
    btest.transunion_has_household_index_fin_3,
    idata.transunion_has_household_index_fin_3
  ) AS transunion_has_household_index_fin_3,
  COALESCE(
    btest.transunion_has_household_index_fin_4,
    idata.transunion_has_household_index_fin_4
  ) AS transunion_has_household_index_fin_4,
  COALESCE(
    btest.transunion_has_household_index_fin_5,
    idata.transunion_has_household_index_fin_5
  ) AS transunion_has_household_index_fin_5,
  COALESCE(
    btest.transunion_has_household_index_tele_1,
    idata.transunion_has_household_index_tele_1
  ) AS transunion_has_household_index_tele_1,
  COALESCE(
    btest.transunion_has_household_index_tele_2,
    idata.transunion_has_household_index_tele_2
  ) AS transunion_has_household_index_tele_2,
  COALESCE(
    btest.transunion_has_household_index_tele_3,
    idata.transunion_has_household_index_tele_3
  ) AS transunion_has_household_index_tele_3,
  COALESCE(
    btest.transunion_has_household_index_tele_4,
    idata.transunion_has_household_index_tele_4
  ) AS transunion_has_household_index_tele_4,
  COALESCE(
    btest.transunion_has_household_index_tele_5,
    idata.transunion_has_household_index_tele_5
  ) AS transunion_has_household_index_tele_5,
  COALESCE(
    btest.transunion_has_household_gt_high_school,
    idata.transunion_has_household_gt_high_school
  ) AS transunion_has_household_gt_high_school,
  COALESCE(
    btest.transunion_has_household_qsa,
    idata.transunion_has_household_qsa
  ) AS transunion_has_household_qsa,
  COALESCE(
    btest.transunion_has_high_income_class,
    idata.transunion_has_high_income_class
  ) AS transunion_has_high_income_class,
  COALESCE(
    btest.transunion_has_household_gt_graduate,
    idata.transunion_has_household_gt_graduate
  ) AS transunion_has_household_gt_graduate,
  COALESCE(
    btest.transunion_has_bolsa_familia,
    idata.transunion_has_bolsa_familia
  ) AS transunion_has_bolsa_familia
FROM
  backtest btest
  FULL OUTER JOIN
    internal_data AS idata
      ON btest.id_proposal = idata.id_proposal
      AND btest.id_proponent = idata.id_proponent
      AND btest.cpf = idata.cpf