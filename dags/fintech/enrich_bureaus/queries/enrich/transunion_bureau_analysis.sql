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
  datalake_static_files.bureaus_transunion_historical AS btest
  FULL OUTER JOIN
    datalake_bureaus.transunion_internal_integration_report AS idata
      ON btest.id_proposal = idata.id_proposal
      AND btest.id_proponent = idata.id_proponent
      AND btest.cpf = idata.cpf
