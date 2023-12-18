WITH integration_report_aud AS (
  SELECT
    rev,
    CAST(REPLACE(REPLACE(cpf, ".", ""), "-", "") AS BIGINT) AS cpf,
    integration_provider,
    REPLACE(
      REPLACE(
        REPLACE(attributes, "Valor - ", ""),
        "Quantidade - ",
        ""
      ),
      "Discreta - ",
      ""
    ) AS attributes
  FROM
    datalake_arquivo_confidencial_clean.integration_report_aud
),
integration_report_data AS (
  SELECT
    cpf,
    GET_JSON_OBJECT(attributes, "$.class_banc_ult_decl") AS transunion_irpf_last_decl_class,
    CAST(
      GET_JSON_OBJECT(attributes, "$.ind_estab_emprego") AS FLOAT
    ) AS transunion_index_job_stability,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_12") AS FLOAT
    ) AS transunion_index_seg_12,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_12_cob") AS FLOAT
    ) AS transunion_index_seg_12_charge,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_12_ecom") AS FLOAT
    ) AS transunion_index_seg_12_ecom,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_12_fin") AS FLOAT
    ) AS transunion_index_seg_12_fin,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_12_tele") AS FLOAT
    ) AS transunion_index_seg_12_tele,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_24") AS FLOAT
    ) AS transunion_index_seg_24,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_24_cob") AS FLOAT
    ) AS transunion_index_seg_24_charge,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_24_ecom") AS FLOAT
    ) AS transunion_index_seg_24_ecom,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_24_fin") AS FLOAT
    ) AS transunion_index_seg_24_fin,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_24_tele") AS FLOAT
    ) AS transunion_index_seg_24_tele,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_6") AS FLOAT
    ) AS transunion_index_seg_6,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_6_cob") AS FLOAT
    ) AS transunion_index_seg_6_cob,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_6_ecom") AS FLOAT
    ) AS transunion_index_seg_6_ecom,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_6_fin") AS FLOAT
    ) AS transunion_index_seg_6_fin,
    CAST(
      GET_JSON_OBJECT(attributes, "$.indic_seg_6_tele") AS FLOAT
    ) AS transunion_index_seg_6_tele,
    CAST(
      CASE
        WHEN GET_JSON_OBJECT(attributes, "$.porte_empregador") = 'Sem informação ou empresa não possui porte' THEN 0.0
        WHEN GET_JSON_OBJECT(attributes, "$.porte_empregador") = 'Micro empresa' THEN 1.0
        WHEN GET_JSON_OBJECT(attributes, "$.porte_empregador") = 'Pequena empresa' THEN 2.0
        WHEN GET_JSON_OBJECT(attributes, "$.porte_empregador") = 'Média empresa' THEN 3.0
        WHEN GET_JSON_OBJECT(attributes, "$.porte_empregador") = 'Grande empresa' THEN 4.0
      END AS FLOAT
    ) AS transunion_employer_size,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_situacao") AS FLOAT
    ) AS transunion_sc_situation,
    CAST(
      GET_JSON_OBJECT(attributes, "$.automoveis_percap_m_munic") AS FLOAT
    ) AS transunion_percap_m_munic_cars,
    CAST(
      GET_JSON_OBJECT(attributes, "$.caminhao_percap_m_munic") AS FLOAT
    ) AS transunion_percap_m_munic_trucks,
    CAST(
      GET_JSON_OBJECT(attributes, "$.caminonete_percap_m_munic") AS FLOAT
    ) AS transunion_percap_m_munic_pickups,
    CAST(
      GET_JSON_OBJECT(attributes, "$.utilitario_percap_m_munic") AS FLOAT
    ) AS transunion_percap_m_munic_utilitario,
    CAST(
      GET_JSON_OBJECT(attributes, "$.veic_outros_percap_m_munic") AS FLOAT
    ) AS transunion_percap_m_munic_others,
    CAST(
      GET_JSON_OBJECT(attributes, "$.dist_centro_m") AS FLOAT
    ) AS transunion_dist_cep_to_city_center,
    CAST(
      GET_JSON_OBJECT(attributes, "$.dist_fronteira_m") AS FLOAT
    ) AS transunion_dist_cep_to_nearest_border,
    CAST(
      GET_JSON_OBJECT(attributes, "$.dist_risco_m") AS FLOAT
    ) AS transunion_dist_cep_to_nearest_subnormal_aglomerate,
    CAST(
      GET_JSON_OBJECT(attributes, "$.idade_media") AS FLOAT
    ) AS transunion_avg_cep_residents_age,
    CAST(GET_JSON_OBJECT(attributes, "$.idhm") AS FLOAT) AS transunion_idhm,
    CAST(
      GET_JSON_OBJECT(attributes, "$.leito_priv_percap_mm_munic") AS FLOAT
    ) AS transunion_percap_mm_munic_private_hosp_beds,
    CAST(
      GET_JSON_OBJECT(attributes, "$.leito_pub_percap_mm_munic") AS FLOAT
    ) AS transunion_percap_mm_munic_public_hosp_beds,
    CAST(
      GET_JSON_OBJECT(attributes, "$.leito_sus_percap_mm_munic") AS FLOAT
    ) AS transunion_percap_mm_munic_sus_hosp_beds,
    CAST(
      GET_JSON_OBJECT(attributes, "$.max_decl_10_hh") AS FLOAT
    ) AS transunion_max_household_irpf_decl_10_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.max_decl_3_hh") AS FLOAT
    ) AS transunion_max_household_irpf_decl_3_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.max_decl_6_hh") AS FLOAT
    ) AS transunion_max_household_irpf_decl_6_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.max_idade_hh") AS FLOAT
    ) AS transunion_max_household_age,
    CAST(
      GET_JSON_OBJECT(attributes, "$.max_ind_estab_emprego_hh") AS FLOAT
    ) AS transunion_max_household_index_job_stability,
    CAST(
      GET_JSON_OBJECT(attributes, "$.max_porte_empregador_hh") AS FLOAT
    ) AS transunion_max_household_employer_size,
    CAST(
      GET_JSON_OBJECT(attributes, "$.max_porte_qsa_hh") AS FLOAT
    ) AS transunion_max_household_qsa_size,
    CAST(
      GET_JSON_OBJECT(attributes, "$.max_renda_pres_hh") AS FLOAT
    ) AS transunion_max_household_presumed_income,
    CAST(
      GET_JSON_OBJECT(attributes, "$.media_idade_hh") AS FLOAT
    ) AS transunion_avg_household_age,
    CAST(
      GET_JSON_OBJECT(attributes, "$.media_renda_pres_hh") AS FLOAT
    ) AS transunion_avg_household_presumed_income,
    CAST(
      GET_JSON_OBJECT(attributes, "$.media_renda_presumida") AS FLOAT
    ) AS transunion_avg_cep_residents_presumed_income,
    CAST(
      GET_JSON_OBJECT(attributes, "$.min_idade_hh") AS FLOAT
    ) AS transunion_min_household_age,
    CAST(
      GET_JSON_OBJECT(attributes, "$.min_renda_pres_hh") AS FLOAT
    ) AS transunion_min_household_presumed_income,
    CAST(
      GET_JSON_OBJECT(attributes, "$.moto_percap_m_munic") AS FLOAT
    ) AS transunion_percap_m_munic_motorcycles,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_00_17") AS FLOAT
    ) AS transunion_percent_cep_residents_00_17_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_18_29") AS FLOAT
    ) AS transunion_percent_cep_residents_18_29_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_30_39") AS FLOAT
    ) AS transunion_percent_cep_residents_30_39_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_40_49") AS FLOAT
    ) AS transunion_percent_cep_residents_40_49_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_50_59") AS FLOAT
    ) AS transunion_percent_cep_residents_50_59_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_60_69") AS FLOAT
    ) AS transunion_percent_cep_residents_60_69_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_70_mais") AS FLOAT
    ) AS transunion_percent_cep_residents_gt_70_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_bolsa_familia") AS FLOAT
    ) AS transunion_percent_cep_residents_bolsa_familia,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_10_00") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_10_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_10_01") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_10_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_10_02_04") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_10_02_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_10_05_09") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_10_05_09,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_10_10") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_10_10,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_pagar_10_00") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_pend_10_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_pagar_10_01") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_pend_10_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_pagar_10_02_04") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_pend_10_02_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_pagar_10_05_09") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_pend_10_05_09,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_pagar_10_10") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_pend_10_10,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_rest_10_00") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_rest_10_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_rest_10_01") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_rest_10_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_rest_10_02_04") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_rest_10_02_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_rest_10_05_09") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_rest_10_05_09,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_decl_rest_10_10") AS FLOAT
    ) AS transunion_percent_cep_residents_irpf_decl_rest_10_10,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_escol_00") AS FLOAT
    ) AS transunion_percent_cep_residents_escol_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_escol_01") AS FLOAT
    ) AS transunion_percent_cep_residents_escol_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_escol_02") AS FLOAT
    ) AS transunion_percent_cep_residents_escol_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_escol_03") AS FLOAT
    ) AS transunion_percent_cep_residents_escol_03,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_escol_04") AS FLOAT
    ) AS transunion_percent_cep_residents_escol_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_escol_05") AS FLOAT
    ) AS transunion_percent_cep_residents_escol_05,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_escol_06") AS FLOAT
    ) AS transunion_percent_cep_residents_escol_06,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_escol_07") AS FLOAT
    ) AS transunion_percent_cep_residents_escol_07,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_escol_08") AS FLOAT
    ) AS transunion_percent_cep_residents_escol_08,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_escol_09") AS FLOAT
    ) AS transunion_percent_cep_residents_escol_09,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_escol_10") AS FLOAT
    ) AS transunion_percent_cep_residents_escol_10,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_func_pub") AS FLOAT
    ) AS transunion_percent_cep_residents_public_employee,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_indic_00") AS FLOAT
    ) AS transunion_percent_cep_residents_registration_rules_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_indic_01") AS FLOAT
    ) AS transunion_percent_cep_residents_registration_rules_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_indic_02") AS FLOAT
    ) AS transunion_percent_cep_residents_registration_rules_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_indic_03") AS FLOAT
    ) AS transunion_percent_cep_residents_registration_rules_03,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_indic_04") AS FLOAT
    ) AS transunion_percent_cep_residents_registration_rules_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_pop_urbana_munic") AS FLOAT
    ) AS transunion_percent_urban_population_munic,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_renda_01") AS FLOAT
    ) AS transunion_percent_cep_residents_presumed_income_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_renda_02") AS FLOAT
    ) AS transunion_percent_cep_residents_presumed_income_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_renda_03") AS FLOAT
    ) AS transunion_percent_cep_residents_presumed_income_03,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_renda_04") AS FLOAT
    ) AS transunion_percent_cep_residents_presumed_income_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_renda_05") AS FLOAT
    ) AS transunion_percent_cep_residents_presumed_income_05,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_renda_06") AS FLOAT
    ) AS transunion_percent_cep_residents_presumed_income_06,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_renda_07") AS FLOAT
    ) AS transunion_percent_cep_residents_presumed_income_07,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_alto") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_high,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_baixo") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_low,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_medio") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_mid,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_cob_alto") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_charge_high,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_cob_baixo") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_charge_low,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_cob_medio") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_charge_mid,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_ecom_alto") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_ecom_high,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_ecom_baixo") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_ecom_low,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_ecom_medio") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_ecom_mid,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_fin_alto") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_fin_high,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_fin_baixo") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_fin_low,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_fin_medio") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_fin_mid,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_muito_alto") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_very_high,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_muito_baixo") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_very_low,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_tele_alto") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_tele_high,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_tele_baixo") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_tele_low,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_tele_medio") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_tele_mid,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_segmento_tele_muito_alto") AS FLOAT
    ) AS transunion_percent_cep_residents_seg_tele_very_high,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.percent_segmento_tele_muito_baixo"
      ) AS FLOAT
    ) AS transunion_percent_cep_residents_seg_tele_very_low,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_sexo_f") AS FLOAT
    ) AS transunion_percent_cep_residents_female,
    CAST(
      GET_JSON_OBJECT(attributes, "$.percent_sexo_m") AS FLOAT
    ) AS transunion_percent_cep_residents_male,
    CAST(
      GET_JSON_OBJECT(attributes, "$.pib_perc_munic") AS FLOAT
    ) AS transunion_percap_pib_munic,
    CAST(
      GET_JSON_OBJECT(attributes, "$.pib_percent_agro_munic") AS FLOAT
    ) AS transunion_percent_pib_agro_munic,
    CAST(
      GET_JSON_OBJECT(attributes, "$.pib_percent_ind_munic") AS FLOAT
    ) AS transunion_percent_pib_ind_munic,
    CAST(
      GET_JSON_OBJECT(attributes, "$.pib_percent_serv_munic") AS FLOAT
    ) AS transunion_percent_pib_serv_munic,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_decl_10") AS FLOAT
    ) AS transunion_qtd_irpf_decl_10_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_decl_3") AS FLOAT
    ) AS transunion_qtd_irpf_decl_3_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_decl_6") AS FLOAT
    ) AS transunion_qtd_irpf_decl_6_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_decl_isento") AS FLOAT
    ) AS transunion_qtd_irpf_decl_isento,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_decl_pagar_10") AS FLOAT
    ) AS transunion_qtd_irpf_decl_pend_10_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_decl_pagar_3") AS FLOAT
    ) AS transunion_qtd_irpf_decl_pend_3_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_decl_pagar_6") AS FLOAT
    ) AS transunion_qtd_irpf_decl_pend_6_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_decl_rest_10") AS FLOAT
    ) AS transunion_qtd_irpf_decl_rest_10_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_decl_rest_3") AS FLOAT
    ) AS transunion_qtd_irpf_decl_rest_3_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_decl_rest_6") AS FLOAT
    ) AS transunion_qtd_irpf_decl_rest_6_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_email") AS FLOAT
    ) AS transunion_qtd_doc_distinct_emails,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_endereco") AS FLOAT
    ) AS transunion_qtd_doc_distinct_addresses,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_ind_estab_emprego_hh") AS FLOAT
    ) AS transunion_qtd_household_index_job_stability,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_pessoas_hh") AS FLOAT
    ) AS transunion_qtd_household_persons,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_tel_cel") AS FLOAT
    ) AS transunion_qtd_doc_distinct_tel_cel,
    CAST(
      GET_JSON_OBJECT(attributes, "$.qtd_tel_fixo") AS FLOAT
    ) AS transunion_qtd_doc_distinct_tel_fixo,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_idade_media") AS FLOAT
    ) AS transunion_avg_sc_age,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_media_morador") AS FLOAT
    ) AS transunion_avg_sc_resident,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_media_renda_presumida") AS FLOAT
    ) AS transunion_avg_sc_presumed_income,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_00_17") AS FLOAT
    ) AS transunion_percent_sc_00_17_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_18_29") AS FLOAT
    ) AS transunion_percent_sc_18_29_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_30_39") AS FLOAT
    ) AS transunion_percent_sc_30_39_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_40_49") AS FLOAT
    ) AS transunion_percent_sc_40_49_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_50_59") AS FLOAT
    ) AS transunion_percent_sc_50_59_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_60_69") AS FLOAT
    ) AS transunion_percent_sc_60_69_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_70_95") AS FLOAT
    ) AS transunion_percent_sc_70_95_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_bolsa_familia") AS FLOAT
    ) AS transunion_percent_sc_bolsa_familia,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_00") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_01") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_02") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_03") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_03,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_04") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_cob_00") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_charge_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_cob_01") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_charge_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_cob_02") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_charge_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_ecom_00") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_ecom_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_ecom_01") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_ecom_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_ecom_02") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_ecom_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_fin_00") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_fin_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_fin_01") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_fin_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_fin_02") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_fin_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_tele_00") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_tele_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_tele_01") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_tele_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_tele_02") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_tele_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_tele_03") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_tele_03,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_consultas_12_tele_04") AS FLOAT
    ) AS transunion_percent_sc_consultas_12_tele_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_10_00") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_10_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_10_01") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_10_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_10_02") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_10_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_10_03") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_10_03,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_10_04") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_10_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_pagar_10_00") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_pend_10_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_pagar_10_01") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_pend_10_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_pagar_10_02") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_pend_10_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_pagar_10_03") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_pend_10_03,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_pagar_10_04") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_pend_10_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_rest_10_00") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_rest_10_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_rest_10_01") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_rest_10_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_rest_10_02") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_rest_10_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_rest_10_03") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_rest_10_03,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_decl_rest_10_04") AS FLOAT
    ) AS transunion_percent_sc_irpf_decl_rest_10_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_1_banheiro") AS FLOAT
    ) AS transunion_percent_sc_residence_1_bathroom,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_1_morador") AS FLOAT
    ) AS transunion_percent_sc_residence_1_resident,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_2_banheiros") AS FLOAT
    ) AS transunion_percent_sc_residence_2_bathrooms,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_2_morador") AS FLOAT
    ) AS transunion_percent_sc_residence_2_residents,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_3_morador") AS FLOAT
    ) AS transunion_percent_sc_residence_3_residents,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_4_morador") AS FLOAT
    ) AS transunion_percent_sc_residence_4_residents,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_adquiridos_outras_formas"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_other_ways,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_agua_rede_geral"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_water_supply,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_alugados") AS FLOAT
    ) AS transunion_percent_sc_residence_rent,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_apartamento") AS FLOAT
    ) AS transunion_percent_sc_residence_apartments,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_banheiro_uso_exclusivo"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_exclusive_bathroom,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_casa") AS FLOAT
    ) AS transunion_percent_sc_residence_houses,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_casa_em_condominio_vila"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_condo_houses,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_coleta_lixo") AS FLOAT
    ) AS transunion_percent_sc_residence_garbage_collection,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_coletado_cacamba"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_garbage_collection_cacamba,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_coletado_outras_formas"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_garbage_collection_other_ways,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_coletado_servico_limpeza"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_garbage_collection_cleanup_service,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_com_esgoto_ceu_aberto"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_open_sewer,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_com_lixo_acumulado"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_accumulated_garbage,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_em_aquisicao") AS FLOAT
    ) AS transunion_percent_sc_residence_in_acquiring,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_energia_eletrica"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_electrical_supply,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_energia_eletrica_medidor_compartil"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_energy_meter_shared,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_energia_eletrica_medidor_exclusivo"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_energy_meter_exclusive,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_energia_eletrica_outras_formas"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_energy_meter_other_ways,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_energia_eletrica_rede_distribuicao"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_power_distribution_network,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_energia_eletrica_sem_medidor"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_energy_meter_without,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_esgoto_demais") AS FLOAT
    ) AS transunion_percent_sc_residence_sewage_too_much,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_esgoto_fossa_septica"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_sewage_septic_tank,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_esgoto_rede_publica"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_sewage_public_network,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_mais_2_banheiros"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_gt_2_bathrooms,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_mais_4_morador") AS FLOAT
    ) AS transunion_percent_sc_residence_gt_4_residents,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_moradia_adequada"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_adequate_housing,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_moradia_inadequada"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_inadequate_housing,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_moradia_semi_adequada"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_semi_adequate_housing,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_permanentes") AS FLOAT
    ) AS transunion_percent_sc_residence_permanent_residents,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_quitados") AS FLOAT
    ) AS transunion_percent_sc_residence_paid_off,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_rendimento_mensal_acima_10_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_monthly_income_gt_10sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_rendimento_mensal_ate_1s8_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_monthly_income_until_1s8_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_rendimento_mensal_de_1_a_2_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_monthly_income_1_a_2_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_rendimento_mensal_de_1s2_a_1_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_monthly_income_1s2_a_1_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_rendimento_mensal_de_1s4_a_1s2_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_monthly_income_1s4_a_1s2_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_rendimento_mensal_de_1s8_a_1s4_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_monthly_income_1s8_a_1s4_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_rendimento_mensal_de_2_a_3_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_monthly_income_2_a_3_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_rendimento_mensal_de_3_a_5_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_monthly_income_3_a_5_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_rendimento_mensal_de_5_a_10_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_monthly_income_5_a_10_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_sem_arborizacao"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_afforestation_without,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_sem_bueiro") AS FLOAT
    ) AS transunion_percent_sc_residence_manhole_without,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_sem_calcada") AS FLOAT
    ) AS transunion_percent_sc_residence_sidewalk_without,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_domici_sem_guia") AS FLOAT
    ) AS transunion_percent_sc_residence_curb_without,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_sem_identificacao_logradouro"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_public_place_without,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_sem_iluminacao_publica"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_public_energy_without,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_sem_morador_feminino"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_female_resident_without,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_sem_morador_masculino"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_male_resident_without,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_sem_pavimentacao"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_paving_without,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_sem_rampa_acessibilidade"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_accessibility_ramp_without,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_domici_sem_rendimento_mensal"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_monthly_income_without,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_escol_00") AS FLOAT
    ) AS transunion_percent_sc_escol_00,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_escol_01") AS FLOAT
    ) AS transunion_percent_sc_escol_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_escol_02") AS FLOAT
    ) AS transunion_percent_sc_escol_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_escol_03") AS FLOAT
    ) AS transunion_percent_sc_escol_03,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_escol_04") AS FLOAT
    ) AS transunion_percent_sc_escol_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_escol_05") AS FLOAT
    ) AS transunion_percent_sc_escol_05,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_escol_06") AS FLOAT
    ) AS transunion_percent_sc_escol_06,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_escol_07") AS FLOAT
    ) AS transunion_percent_sc_escol_07,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_escol_08") AS FLOAT
    ) AS transunion_percent_sc_escol_08,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_escol_09") AS FLOAT
    ) AS transunion_percent_sc_escol_09,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_escol_10") AS FLOAT
    ) AS transunion_percent_sc_escol_10,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_func_pub") AS FLOAT
    ) AS transunion_percent_sc_public_employee,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_morador_agua_rede_geral"
      ) AS FLOAT
    ) AS transunion_percent_sc_resident_water_supply,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_morador_apartamento") AS FLOAT
    ) AS transunion_percent_sc_resident_apartment,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_morador_casa") AS FLOAT
    ) AS transunion_percent_sc_resident_house,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_morador_casa_condominio_vila"
      ) AS FLOAT
    ) AS transunion_percent_sc_resident_condo_house,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_morador_coleta_lixo") AS FLOAT
    ) AS transunion_percent_sc_resident_garbage_collection,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_morador_coleta_lixo_servico"
      ) AS FLOAT
    ) AS transunion_percent_sc_resident_gargabe_collection_service,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_morador_domici_adquiridos_outras_formas"
      ) AS FLOAT
    ) AS transunion_percent_sc_resident_residence_acquired_other_ways,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_morador_domici_alugado"
      ) AS FLOAT
    ) AS transunion_percent_sc_resident_residence_rent,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_morador_domici_em_aquisicao"
      ) AS FLOAT
    ) AS transunion_percent_sc_resident_residence_in_acquisition,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_morador_domici_permanente"
      ) AS FLOAT
    ) AS transunion_percent_sc_resident_residence_permanent,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_morador_domici_quitado"
      ) AS FLOAT
    ) AS transunion_percent_sc_resident_residence_paid_off,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_morador_energia_eletrica"
      ) AS FLOAT
    ) AS transunion_percent_sc_resident_residence_electrical_supply,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_0_4_anos") AS FLOAT
    ) AS transunion_percent_people_0_4_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_10_14_anos") AS FLOAT
    ) AS transunion_percent_people_10_14_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_15_17_anos") AS FLOAT
    ) AS transunion_percent_people_15_17_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_18_19_anos") AS FLOAT
    ) AS transunion_percent_people_18_19_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_20_24_anos") AS FLOAT
    ) AS transunion_percent_people_20_24_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_25_29_anos") AS FLOAT
    ) AS transunion_percent_people_25_29_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_30_34_anos") AS FLOAT
    ) AS transunion_percent_people_30_34_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_35_39_anos") AS FLOAT
    ) AS transunion_percent_people_35_39_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_40_44_anos") AS FLOAT
    ) AS transunion_percent_people_40_44_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_45_49_anos") AS FLOAT
    ) AS transunion_percent_people_45_49_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_50_54_anos") AS FLOAT
    ) AS transunion_percent_people_50_54_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_55_59_anos") AS FLOAT
    ) AS transunion_percent_people_55_59_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_5_9_anos") AS FLOAT
    ) AS transunion_percent_people_5_9_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_60_69_anos") AS FLOAT
    ) AS transunion_percent_people_60_69_years,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_com_registro_nascimento"
      ) AS FLOAT
    ) AS transunion_percent_people_registration_birth,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_pessoas_mais_69_anos") AS FLOAT
    ) AS transunion_percent_people_gt_69_years,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_nao_sabem_registro_nascimento"
      ) AS FLOAT
    ) AS transunion_percent_people_registration_birth_not_known,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_rendimento_mensal_10_a_15_sm"
      ) AS FLOAT
    ) AS transunion_percent_people_monthly_income_10_a_15_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_rendimento_mensal_15_a_20_sm"
      ) AS FLOAT
    ) AS transunion_percent_people_monthly_income_15_a_20_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_rendimento_mensal_1_a_2_sm"
      ) AS FLOAT
    ) AS transunion_percent_people_monthly_income_1_a_2_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_rendimento_mensal_1s2_a_1_sm"
      ) AS FLOAT
    ) AS transunion_percent_people_monthly_income_1s2_a_1_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_rendimento_mensal_2_a_3_sm"
      ) AS FLOAT
    ) AS transunion_percent_people_monthly_income_2_a_3_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_rendimento_mensal_3_a_5_sm"
      ) AS FLOAT
    ) AS transunion_percent_people_monthly_income_3_a_5_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_rendimento_mensal_5_a_10_sm"
      ) AS FLOAT
    ) AS transunion_percent_people_monthly_income_5_a_10_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_rendimento_mensal_acima_20_sm"
      ) AS FLOAT
    ) AS transunion_percent_people_monthly_income_gt_20_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_rendimento_mensal_ate_1s2_sm"
      ) AS FLOAT
    ) AS transunion_percent_people_monthly_income_until_1s2_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_sem_registro_nascimento"
      ) AS FLOAT
    ) AS transunion_percent_people_registration_birth_without,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_pessoas_sem_rendimento_mensal"
      ) AS FLOAT
    ) AS transunion_percent_people_monthly_income_without,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_renda_01") AS FLOAT
    ) AS transunion_percent_sc_income_01,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_renda_02") AS FLOAT
    ) AS transunion_percent_sc_income_02,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_renda_03") AS FLOAT
    ) AS transunion_percent_sc_income_03,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_renda_04") AS FLOAT
    ) AS transunion_percent_sc_income_04,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_renda_05") AS FLOAT
    ) AS transunion_percent_sc_income_05,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_renda_06") AS FLOAT
    ) AS transunion_percent_sc_income_06,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_renda_07") AS FLOAT
    ) AS transunion_percent_sc_income_07,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_domici_alfabetizado_feminino"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_literate_female,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_domici_alfabetizado_masculino"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_literate_male,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_domici_sexo_feminino"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_female,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_domici_sexo_masculino"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_male,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_rendimento_mensal_10_a_15_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_monthly_income_10_a_15_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_rendimento_mensal_15_a_20_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_monthly_income_15_a_20_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_rendimento_mensal_1_a_2_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_monthly_income_1_a_2_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_rendimento_mensal_1s2_a_1_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_monthly_income_1s2_a_1_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_rendimento_mensal_2_a_3_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_monthly_income_2_a_3_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_rendimento_mensal_3_a_5_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_monthly_income_3_a_5_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_rendimento_mensal_5_a_10_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_monthly_income_5_a_10_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_rendimento_mensal_acima_20_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_monthly_income_gt_20_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_rendimento_mensal_ate_1s2_sm"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_monthly_income_until_1s2_sm,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_percent_responsa_sem_rendimento_mensal"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_monthly_income_without,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_sexo_f") AS FLOAT
    ) AS transunion_percent_sc_female,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percent_sexo_m") AS FLOAT
    ) AS transunion_percent_sc_male,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sc_percentual_qsa") AS FLOAT
    ) AS transunion_percent_sc_qsa,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_rendimento_medio_mensal_domici_salario_minimo"
      ) AS FLOAT
    ) AS transunion_percent_sc_residence_avg_monthly_income_salario_minimo,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_rendimento_medio_mensal_respons_domici_salario_minimo"
      ) AS FLOAT
    ) AS transunion_percent_sc_responsible_person_avg_monthly_income_salario_minimo,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_valor_rendimento_mensal_pessoas_sm"
      ) AS FLOAT
    ) AS transunion_sum_sc_persons_monthly_income_gt_10_years,
    CAST(
      GET_JSON_OBJECT(
        attributes,
        "$.sc_valor_rendimento_mensal_responsa_sm"
      ) AS FLOAT
    ) AS transunion_sum_sc_responsible_persons_monthly_income,
    CAST(
      GET_JSON_OBJECT(attributes, "$.sum_renda_pres_hh") AS FLOAT
    ) AS transunion_sum_household_presumed_income,
    CAST(
      GET_JSON_OBJECT(attributes, "$.tempo_emissao_cpf") AS FLOAT
    ) AS transunion_time_cpf_emission,
    CAST(
      GET_JSON_OBJECT(attributes, "$.tmp_meses_ult_tel_cel") AS FLOAT
    ) AS transunion_time_months_last_cel_phone,
    CAST(
      GET_JSON_OBJECT(attributes, "$.tmp_meses_ult_tel_fixo") AS FLOAT
    ) AS transunion_time_months_last_tel_fixo,
    CAST(
      GET_JSON_OBJECT(attributes, "$.tmp_ult_decl_a_restit") AS FLOAT
    ) AS transunion_time_last_irpf_decl_rest,
    CAST(
      GET_JSON_OBJECT(attributes, "$.tmpo_ult_decl") AS FLOAT
    ) AS transunion_time_last_irpf_decl,
    CAST(
      GET_JSON_OBJECT(attributes, "$.tmpo_ult_decl_a_pagar") AS FLOAT
    ) AS transunion_time_last_irpf_decl_pend,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_11_15_anos_hh") AS FLOAT
    ) AS transunion_has_household_11_15_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_16_17_anos_hh") AS FLOAT
    ) AS transunion_has_household_16_17_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_18_20_anos_hh") AS FLOAT
    ) AS transunion_has_household_18_20_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_21_25_anos_hh") AS FLOAT
    ) AS transunion_has_household_21_25_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_25_30_anos_hh") AS FLOAT
    ) AS transunion_has_household_25_30_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_3_5_anos_hh") AS FLOAT
    ) AS transunion_has_household_3_5_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_6_10_anos_hh") AS FLOAT
    ) AS transunion_has_household_6_10_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_ate_2_anos_hh") AS FLOAT
    ) AS transunion_has_household_until_2_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_func_pub") AS FLOAT
    ) AS transunion_is_public_employee,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_socio") AS FLOAT
    ) AS transunion_is_business_partner,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_tel_cel_procon") AS FLOAT
    ) AS transunion_is_tel_cel_procon,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_tel_fixo_assin") AS FLOAT
    ) AS transunion_is_tel_fixo_assin,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_tel_fixo_procon") AS FLOAT
    ) AS transunion_is_tel_fixo_procon,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_bolsa_familia_hh") AS FLOAT
    ) AS transunion_has_household_bolsa_familia,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_decl_10_hh") AS FLOAT
    ) AS transunion_has_household_irpf_decl_10_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_decl_3_hh") AS FLOAT
    ) AS transunion_has_household_irpf_decl_3_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_decl_6_hh") AS FLOAT
    ) AS transunion_has_household_irpf_decl_6_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_decl_pagar_10_hh") AS FLOAT
    ) AS transunion_has_household_irpf_decl_pend_10_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_decl_pagar_3_hh") AS FLOAT
    ) AS transunion_has_household_irpf_decl_pend_3_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_decl_pagar_6_hh") AS FLOAT
    ) AS transunion_has_household_irpf_decl_pend_6_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_decl_rest_10a_hh") AS FLOAT
    ) AS transunion_has_household_irpf_decl_rest_10_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_decl_rest_3a_hh") AS FLOAT
    ) AS transunion_has_household_irpf_decl_rest_3_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_decl_rest_6a_hh") AS FLOAT
    ) AS transunion_has_household_irpf_decl_rest_6_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_func_pub_hh") AS FLOAT
    ) AS transunion_has_household_public_employee,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_idade_35_hh") AS FLOAT
    ) AS transunion_has_household_gt_35_years,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_ind_estab_emprego_hh") AS FLOAT
    ) AS transunion_has_household_index_job_stability,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indicador_hh") AS FLOAT
    ) AS transunion_has_household_invalid_registration_rules,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_cob_1_hh") AS FLOAT
    ) AS transunion_has_household_index_charge_1,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_cob_2_hh") AS FLOAT
    ) AS transunion_has_household_index_charge_2,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_cob_3_hh") AS FLOAT
    ) AS transunion_has_household_index_charge_3,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_cob_4_hh") AS FLOAT
    ) AS transunion_has_household_index_charge_4,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_cob_5_hh") AS FLOAT
    ) AS transunion_has_household_index_charge_5,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_ecom_1_hh") AS FLOAT
    ) AS transunion_has_household_index_ecom_1,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_ecom_2_hh") AS FLOAT
    ) AS transunion_has_household_index_ecom_2,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_ecom_3_hh") AS FLOAT
    ) AS transunion_has_household_index_ecom_3,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_ecom_4_hh") AS FLOAT
    ) AS transunion_has_household_index_ecom_4,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_ecom_5_hh") AS FLOAT
    ) AS transunion_has_household_index_ecom_5,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_fin_1_hh") AS FLOAT
    ) AS transunion_has_household_index_fin_1,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_fin_2_hh") AS FLOAT
    ) AS transunion_has_household_index_fin_2,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_fin_3_hh") AS FLOAT
    ) AS transunion_has_household_index_fin_3,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_fin_4_hh") AS FLOAT
    ) AS transunion_has_household_index_fin_4,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_fin_5_hh") AS FLOAT
    ) AS transunion_has_household_index_fin_5,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_tele_1_hh") AS FLOAT
    ) AS transunion_has_household_index_tele_1,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_tele_2_hh") AS FLOAT
    ) AS transunion_has_household_index_tele_2,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_tele_3_hh") AS FLOAT
    ) AS transunion_has_household_index_tele_3,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_tele_4_hh") AS FLOAT
    ) AS transunion_has_household_index_tele_4,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_indice_tele_5_hh") AS FLOAT
    ) AS transunion_has_household_index_tele_5,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_medio_compl_hh") AS FLOAT
    ) AS transunion_has_household_gt_high_school,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_qsa_hh") AS FLOAT
    ) AS transunion_has_household_qsa,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_rest_agencia_alta_renda") AS FLOAT
    ) AS transunion_has_high_income_class,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flg_superior_compl_hh") AS FLOAT
    ) AS transunion_has_household_gt_graduate,
    CAST(
      GET_JSON_OBJECT(attributes, "$.flag_bolsa_familia") AS FLOAT
    ) AS transunion_has_bolsa_familia,
    revinfo.ts_created AS timestamp
  FROM
    integration_report_aud AS itr
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
    MAX(issued_at) AS last_ca_timestamp
  FROM
    datalake_sorting_hat_clean.screening_result_version sr
    JOIN datalake_sorting_hat_raw.transaction t
        ON sr.id_transaction = t.id
  GROUP BY
    id_proposal
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
        ON itr.cpf = CAST(REPLACE(REPLACE(ppt.cpf,".",""),"-","") AS BIGINT)
        AND itr.timestamp < l_ca.last_ca_timestamp
)
  SELECT
    id_proposal,
    id_proponent,
    cpf,
    transunion_irpf_last_decl_class,
    transunion_index_job_stability,
    transunion_index_seg_12,
    transunion_index_seg_12_charge,
    transunion_index_seg_12_ecom,
    transunion_index_seg_12_fin,
    transunion_index_seg_12_tele,
    transunion_index_seg_24,
    transunion_index_seg_24_charge,
    transunion_index_seg_24_ecom,
    transunion_index_seg_24_fin,
    transunion_index_seg_24_tele,
    transunion_index_seg_6,
    transunion_index_seg_6_cob,
    transunion_index_seg_6_ecom,
    transunion_index_seg_6_fin,
    transunion_index_seg_6_tele,
    transunion_employer_size,
    transunion_sc_situation,
    transunion_percap_m_munic_cars,
    transunion_percap_m_munic_trucks,
    transunion_percap_m_munic_pickups,
    transunion_percap_m_munic_utilitario,
    transunion_percap_m_munic_others,
    transunion_dist_cep_to_city_center,
    transunion_dist_cep_to_nearest_border,
    transunion_dist_cep_to_nearest_subnormal_aglomerate,
    transunion_avg_cep_residents_age,
    transunion_idhm,
    transunion_percap_mm_munic_private_hosp_beds,
    transunion_percap_mm_munic_public_hosp_beds,
    transunion_percap_mm_munic_sus_hosp_beds,
    transunion_max_household_irpf_decl_10_years,
    transunion_max_household_irpf_decl_3_years,
    transunion_max_household_irpf_decl_6_years,
    transunion_max_household_age,
    transunion_max_household_index_job_stability,
    transunion_max_household_employer_size,
    transunion_max_household_qsa_size,
    transunion_max_household_presumed_income,
    transunion_avg_household_age,
    transunion_avg_household_presumed_income,
    transunion_avg_cep_residents_presumed_income,
    transunion_min_household_age,
    transunion_min_household_presumed_income,
    transunion_percap_m_munic_motorcycles,
    transunion_percent_cep_residents_00_17_years,
    transunion_percent_cep_residents_18_29_years,
    transunion_percent_cep_residents_30_39_years,
    transunion_percent_cep_residents_40_49_years,
    transunion_percent_cep_residents_50_59_years,
    transunion_percent_cep_residents_60_69_years,
    transunion_percent_cep_residents_gt_70_years,
    transunion_percent_cep_residents_bolsa_familia,
    transunion_percent_cep_residents_irpf_decl_10_00,
    transunion_percent_cep_residents_irpf_decl_10_01,
    transunion_percent_cep_residents_irpf_decl_10_02_04,
    transunion_percent_cep_residents_irpf_decl_10_05_09,
    transunion_percent_cep_residents_irpf_decl_10_10,
    transunion_percent_cep_residents_irpf_decl_pend_10_00,
    transunion_percent_cep_residents_irpf_decl_pend_10_01,
    transunion_percent_cep_residents_irpf_decl_pend_10_02_04,
    transunion_percent_cep_residents_irpf_decl_pend_10_05_09,
    transunion_percent_cep_residents_irpf_decl_pend_10_10,
    transunion_percent_cep_residents_irpf_decl_rest_10_00,
    transunion_percent_cep_residents_irpf_decl_rest_10_01,
    transunion_percent_cep_residents_irpf_decl_rest_10_02_04,
    transunion_percent_cep_residents_irpf_decl_rest_10_05_09,
    transunion_percent_cep_residents_irpf_decl_rest_10_10,
    transunion_percent_cep_residents_escol_00,
    transunion_percent_cep_residents_escol_01,
    transunion_percent_cep_residents_escol_02,
    transunion_percent_cep_residents_escol_03,
    transunion_percent_cep_residents_escol_04,
    transunion_percent_cep_residents_escol_05,
    transunion_percent_cep_residents_escol_06,
    transunion_percent_cep_residents_escol_07,
    transunion_percent_cep_residents_escol_08,
    transunion_percent_cep_residents_escol_09,
    transunion_percent_cep_residents_escol_10,
    transunion_percent_cep_residents_public_employee,
    transunion_percent_cep_residents_registration_rules_00,
    transunion_percent_cep_residents_registration_rules_01,
    transunion_percent_cep_residents_registration_rules_02,
    transunion_percent_cep_residents_registration_rules_03,
    transunion_percent_cep_residents_registration_rules_04,
    transunion_percent_urban_population_munic,
    transunion_percent_cep_residents_presumed_income_01,
    transunion_percent_cep_residents_presumed_income_02,
    transunion_percent_cep_residents_presumed_income_03,
    transunion_percent_cep_residents_presumed_income_04,
    transunion_percent_cep_residents_presumed_income_05,
    transunion_percent_cep_residents_presumed_income_06,
    transunion_percent_cep_residents_presumed_income_07,
    transunion_percent_cep_residents_seg_high,
    transunion_percent_cep_residents_seg_low,
    transunion_percent_cep_residents_seg_mid,
    transunion_percent_cep_residents_seg_charge_high,
    transunion_percent_cep_residents_seg_charge_low,
    transunion_percent_cep_residents_seg_charge_mid,
    transunion_percent_cep_residents_seg_ecom_high,
    transunion_percent_cep_residents_seg_ecom_low,
    transunion_percent_cep_residents_seg_ecom_mid,
    transunion_percent_cep_residents_seg_fin_high,
    transunion_percent_cep_residents_seg_fin_low,
    transunion_percent_cep_residents_seg_fin_mid,
    transunion_percent_cep_residents_seg_very_high,
    transunion_percent_cep_residents_seg_very_low,
    transunion_percent_cep_residents_seg_tele_high,
    transunion_percent_cep_residents_seg_tele_low,
    transunion_percent_cep_residents_seg_tele_mid,
    transunion_percent_cep_residents_seg_tele_very_high,
    transunion_percent_cep_residents_seg_tele_very_low,
    transunion_percent_cep_residents_female,
    transunion_percent_cep_residents_male,
    transunion_percap_pib_munic,
    transunion_percent_pib_agro_munic,
    transunion_percent_pib_ind_munic,
    transunion_percent_pib_serv_munic,
    transunion_qtd_irpf_decl_10_years,
    transunion_qtd_irpf_decl_3_years,
    transunion_qtd_irpf_decl_6_years,
    transunion_qtd_irpf_decl_isento,
    transunion_qtd_irpf_decl_pend_10_years,
    transunion_qtd_irpf_decl_pend_3_years,
    transunion_qtd_irpf_decl_pend_6_years,
    transunion_qtd_irpf_decl_rest_10_years,
    transunion_qtd_irpf_decl_rest_3_years,
    transunion_qtd_irpf_decl_rest_6_years,
    transunion_qtd_doc_distinct_emails,
    transunion_qtd_doc_distinct_addresses,
    transunion_qtd_household_index_job_stability,
    transunion_qtd_household_persons,
    transunion_qtd_doc_distinct_tel_cel,
    transunion_qtd_doc_distinct_tel_fixo,
    transunion_avg_sc_age,
    transunion_avg_sc_resident,
    transunion_avg_sc_presumed_income,
    transunion_percent_sc_00_17_years,
    transunion_percent_sc_18_29_years,
    transunion_percent_sc_30_39_years,
    transunion_percent_sc_40_49_years,
    transunion_percent_sc_50_59_years,
    transunion_percent_sc_60_69_years,
    transunion_percent_sc_70_95_years,
    transunion_percent_sc_bolsa_familia,
    transunion_percent_sc_consultas_12_00,
    transunion_percent_sc_consultas_12_01,
    transunion_percent_sc_consultas_12_02,
    transunion_percent_sc_consultas_12_03,
    transunion_percent_sc_consultas_12_04,
    transunion_percent_sc_consultas_12_charge_00,
    transunion_percent_sc_consultas_12_charge_01,
    transunion_percent_sc_consultas_12_charge_02,
    transunion_percent_sc_consultas_12_ecom_00,
    transunion_percent_sc_consultas_12_ecom_01,
    transunion_percent_sc_consultas_12_ecom_02,
    transunion_percent_sc_consultas_12_fin_00,
    transunion_percent_sc_consultas_12_fin_01,
    transunion_percent_sc_consultas_12_fin_02,
    transunion_percent_sc_consultas_12_tele_00,
    transunion_percent_sc_consultas_12_tele_01,
    transunion_percent_sc_consultas_12_tele_02,
    transunion_percent_sc_consultas_12_tele_03,
    transunion_percent_sc_consultas_12_tele_04,
    transunion_percent_sc_irpf_decl_10_00,
    transunion_percent_sc_irpf_decl_10_01,
    transunion_percent_sc_irpf_decl_10_02,
    transunion_percent_sc_irpf_decl_10_03,
    transunion_percent_sc_irpf_decl_10_04,
    transunion_percent_sc_irpf_decl_pend_10_00,
    transunion_percent_sc_irpf_decl_pend_10_01,
    transunion_percent_sc_irpf_decl_pend_10_02,
    transunion_percent_sc_irpf_decl_pend_10_03,
    transunion_percent_sc_irpf_decl_pend_10_04,
    transunion_percent_sc_irpf_decl_rest_10_00,
    transunion_percent_sc_irpf_decl_rest_10_01,
    transunion_percent_sc_irpf_decl_rest_10_02,
    transunion_percent_sc_irpf_decl_rest_10_03,
    transunion_percent_sc_irpf_decl_rest_10_04,
    transunion_percent_sc_residence_1_bathroom,
    transunion_percent_sc_residence_1_resident,
    transunion_percent_sc_residence_2_bathrooms,
    transunion_percent_sc_residence_2_residents,
    transunion_percent_sc_residence_3_residents,
    transunion_percent_sc_residence_4_residents,
    transunion_percent_sc_residence_other_ways,
    transunion_percent_sc_residence_water_supply,
    transunion_percent_sc_residence_rent,
    transunion_percent_sc_residence_apartments,
    transunion_percent_sc_residence_exclusive_bathroom,
    transunion_percent_sc_residence_houses,
    transunion_percent_sc_residence_condo_houses,
    transunion_percent_sc_residence_garbage_collection,
    transunion_percent_sc_residence_garbage_collection_cacamba,
    transunion_percent_sc_residence_garbage_collection_other_ways,
    transunion_percent_sc_residence_garbage_collection_cleanup_service,
    transunion_percent_sc_residence_open_sewer,
    transunion_percent_sc_residence_accumulated_garbage,
    transunion_percent_sc_residence_in_acquiring,
    transunion_percent_sc_residence_electrical_supply,
    transunion_percent_sc_residence_energy_meter_shared,
    transunion_percent_sc_residence_energy_meter_exclusive,
    transunion_percent_sc_residence_energy_meter_other_ways,
    transunion_percent_sc_residence_power_distribution_network,
    transunion_percent_sc_residence_energy_meter_without,
    transunion_percent_sc_residence_sewage_too_much,
    transunion_percent_sc_residence_sewage_septic_tank,
    transunion_percent_sc_residence_sewage_public_network,
    transunion_percent_sc_residence_gt_2_bathrooms,
    transunion_percent_sc_residence_gt_4_residents,
    transunion_percent_sc_residence_adequate_housing,
    transunion_percent_sc_residence_inadequate_housing,
    transunion_percent_sc_residence_semi_adequate_housing,
    transunion_percent_sc_residence_permanent_residents,
    transunion_percent_sc_residence_paid_off,
    transunion_percent_sc_residence_monthly_income_gt_10sm,
    transunion_percent_sc_residence_monthly_income_until_1s8_sm,
    transunion_percent_sc_residence_monthly_income_1_a_2_sm,
    transunion_percent_sc_residence_monthly_income_1s2_a_1_sm,
    transunion_percent_sc_residence_monthly_income_1s4_a_1s2_sm,
    transunion_percent_sc_residence_monthly_income_1s8_a_1s4_sm,
    transunion_percent_sc_residence_monthly_income_2_a_3_sm,
    transunion_percent_sc_residence_monthly_income_3_a_5_sm,
    transunion_percent_sc_residence_monthly_income_5_a_10_sm,
    transunion_percent_sc_residence_afforestation_without,
    transunion_percent_sc_residence_manhole_without,
    transunion_percent_sc_residence_sidewalk_without,
    transunion_percent_sc_residence_curb_without,
    transunion_percent_sc_residence_public_place_without,
    transunion_percent_sc_residence_public_energy_without,
    transunion_percent_sc_residence_female_resident_without,
    transunion_percent_sc_residence_male_resident_without,
    transunion_percent_sc_residence_paving_without,
    transunion_percent_sc_residence_accessibility_ramp_without,
    transunion_percent_sc_residence_monthly_income_without,
    transunion_percent_sc_escol_00,
    transunion_percent_sc_escol_01,
    transunion_percent_sc_escol_02,
    transunion_percent_sc_escol_03,
    transunion_percent_sc_escol_04,
    transunion_percent_sc_escol_05,
    transunion_percent_sc_escol_06,
    transunion_percent_sc_escol_07,
    transunion_percent_sc_escol_08,
    transunion_percent_sc_escol_09,
    transunion_percent_sc_escol_10,
    transunion_percent_sc_public_employee,
    transunion_percent_sc_resident_water_supply,
    transunion_percent_sc_resident_apartment,
    transunion_percent_sc_resident_house,
    transunion_percent_sc_resident_condo_house,
    transunion_percent_sc_resident_garbage_collection,
    transunion_percent_sc_resident_gargabe_collection_service,
    transunion_percent_sc_resident_residence_acquired_other_ways,
    transunion_percent_sc_resident_residence_rent,
    transunion_percent_sc_resident_residence_in_acquisition,
    transunion_percent_sc_resident_residence_permanent,
    transunion_percent_sc_resident_residence_paid_off,
    transunion_percent_sc_resident_residence_electrical_supply,
    transunion_percent_people_0_4_years,
    transunion_percent_people_10_14_years,
    transunion_percent_people_15_17_years,
    transunion_percent_people_18_19_years,
    transunion_percent_people_20_24_years,
    transunion_percent_people_25_29_years,
    transunion_percent_people_30_34_years,
    transunion_percent_people_35_39_years,
    transunion_percent_people_40_44_years,
    transunion_percent_people_45_49_years,
    transunion_percent_people_50_54_years,
    transunion_percent_people_55_59_years,
    transunion_percent_people_5_9_years,
    transunion_percent_people_60_69_years,
    transunion_percent_people_registration_birth,
    transunion_percent_people_gt_69_years,
    transunion_percent_people_registration_birth_not_known,
    transunion_percent_people_monthly_income_10_a_15_sm,
    transunion_percent_people_monthly_income_15_a_20_sm,
    transunion_percent_people_monthly_income_1_a_2_sm,
    transunion_percent_people_monthly_income_1s2_a_1_sm,
    transunion_percent_people_monthly_income_2_a_3_sm,
    transunion_percent_people_monthly_income_3_a_5_sm,
    transunion_percent_people_monthly_income_5_a_10_sm,
    transunion_percent_people_monthly_income_gt_20_sm,
    transunion_percent_people_monthly_income_until_1s2_sm,
    transunion_percent_people_registration_birth_without,
    transunion_percent_people_monthly_income_without,
    transunion_percent_sc_income_01,
    transunion_percent_sc_income_02,
    transunion_percent_sc_income_03,
    transunion_percent_sc_income_04,
    transunion_percent_sc_income_05,
    transunion_percent_sc_income_06,
    transunion_percent_sc_income_07,
    transunion_percent_sc_responsible_person_literate_female,
    transunion_percent_sc_responsible_person_literate_male,
    transunion_percent_sc_responsible_person_female,
    transunion_percent_sc_responsible_person_male,
    transunion_percent_sc_responsible_person_monthly_income_10_a_15_sm,
    transunion_percent_sc_responsible_person_monthly_income_15_a_20_sm,
    transunion_percent_sc_responsible_person_monthly_income_1_a_2_sm,
    transunion_percent_sc_responsible_person_monthly_income_1s2_a_1_sm,
    transunion_percent_sc_responsible_person_monthly_income_2_a_3_sm,
    transunion_percent_sc_responsible_person_monthly_income_3_a_5_sm,
    transunion_percent_sc_responsible_person_monthly_income_5_a_10_sm,
    transunion_percent_sc_responsible_person_monthly_income_gt_20_sm,
    transunion_percent_sc_responsible_person_monthly_income_until_1s2_sm,
    transunion_percent_sc_responsible_person_monthly_income_without,
    transunion_percent_sc_female,
    transunion_percent_sc_male,
    transunion_percent_sc_qsa,
    transunion_percent_sc_residence_avg_monthly_income_salario_minimo,
    transunion_percent_sc_responsible_person_avg_monthly_income_salario_minimo,
    transunion_sum_sc_persons_monthly_income_gt_10_years,
    transunion_sum_sc_responsible_persons_monthly_income,
    transunion_sum_household_presumed_income,
    transunion_time_cpf_emission,
    transunion_time_months_last_cel_phone,
    transunion_time_months_last_tel_fixo,
    transunion_time_last_irpf_decl_rest,
    transunion_time_last_irpf_decl,
    transunion_time_last_irpf_decl_pend,
    transunion_has_household_11_15_years,
    transunion_has_household_16_17_years,
    transunion_has_household_18_20_years,
    transunion_has_household_21_25_years,
    transunion_has_household_25_30_years,
    transunion_has_household_3_5_years,
    transunion_has_household_6_10_years,
    transunion_has_household_until_2_years,
    transunion_is_public_employee,
    transunion_is_business_partner,
    transunion_is_tel_cel_procon,
    transunion_is_tel_fixo_assin,
    transunion_is_tel_fixo_procon,
    transunion_has_household_bolsa_familia,
    transunion_has_household_irpf_decl_10_years,
    transunion_has_household_irpf_decl_3_years,
    transunion_has_household_irpf_decl_6_years,
    transunion_has_household_irpf_decl_pend_10_years,
    transunion_has_household_irpf_decl_pend_3_years,
    transunion_has_household_irpf_decl_pend_6_years,
    transunion_has_household_irpf_decl_rest_10_years,
    transunion_has_household_irpf_decl_rest_3_years,
    transunion_has_household_irpf_decl_rest_6_years,
    transunion_has_household_public_employee,
    transunion_has_household_gt_35_years,
    transunion_has_household_index_job_stability,
    transunion_has_household_invalid_registration_rules,
    transunion_has_household_index_charge_1,
    transunion_has_household_index_charge_2,
    transunion_has_household_index_charge_3,
    transunion_has_household_index_charge_4,
    transunion_has_household_index_charge_5,
    transunion_has_household_index_ecom_1,
    transunion_has_household_index_ecom_2,
    transunion_has_household_index_ecom_3,
    transunion_has_household_index_ecom_4,
    transunion_has_household_index_ecom_5,
    transunion_has_household_index_fin_1,
    transunion_has_household_index_fin_2,
    transunion_has_household_index_fin_3,
    transunion_has_household_index_fin_4,
    transunion_has_household_index_fin_5,
    transunion_has_household_index_tele_1,
    transunion_has_household_index_tele_2,
    transunion_has_household_index_tele_3,
    transunion_has_household_index_tele_4,
    transunion_has_household_index_tele_5,
    transunion_has_household_gt_high_school,
    transunion_has_household_qsa,
    transunion_has_high_income_class,
    transunion_has_household_gt_graduate,
    transunion_has_bolsa_familia
  FROM
    enriched_integration_report_data
  WHERE
    max_itr_timestamp = timestamp
    AND DATEDIFF(last_ca_timestamp, max_itr_timestamp) <= 30