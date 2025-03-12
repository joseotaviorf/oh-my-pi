SELECT
    c.proposal_number AS id_propose,
    CASE
        WHEN c.proposal_rating IS NULL THEN 'Missing'
        WHEN c.proposal_rating = 'NaN' THEN 'Missing'
        ELSE c.proposal_rating
    END AS rating,
    c.log_result AS status,
    CASE
      WHEN document_status_federal = 'PENDENTE DE REGULARIZAÇÃO' OR ARRAY_CONTAINS(document_status_federal_list,'PENDENTE DE REGULARIZAÇÃO') OR bigdataboost_document_status = 'PENDENTE DE REGULARIZACAO' OR ARRAY_CONTAINS(bigdataboost_document_status_list, 'PENDENTE DE REGULARIZACAO') THEN 'CPF Pending Regularization'
      WHEN document_status_federal = 'SUSPENSA' OR ARRAY_CONTAINS(document_status_federal_list, 'SUSPENSA') OR bigdataboost_document_status = 'SUSPENSA' OR ARRAY_CONTAINS(bigdataboost_document_status_list, 'SUSPENSA') THEN 'CPF Suspended'
      WHEN document_status_federal = 'NULA' OR ARRAY_CONTAINS(document_status_federal_list, 'NULA') OR bigdataboost_document_status = 'NULA' OR ARRAY_CONTAINS(bigdataboost_document_status_list, 'NULA') THEN 'Null CPF'
      WHEN document_status_federal = 'CANCELADA' OR ARRAY_CONTAINS(document_status_federal_list, 'CANCELADA') OR bigdataboost_document_status = 'CANCELADA' OR ARRAY_CONTAINS(bigdataboost_document_status_list, 'CANCELADA') THEN 'CPF Cancelled'
      WHEN document_status_federal = 'TITULAR FALECIDO' OR ARRAY_CONTAINS(document_status_federal_list, 'TITULAR FALECIDO') OR bigdataboost_document_status = 'TITULAR FALECIDO' OR ARRAY_CONTAINS(bigdataboost_document_status_list, 'TITULAR FALECIDO') THEN 'Deceased Holder'
      ELSE 'CPF Ok'
    END AS status_cpf,
    CASE
      WHEN (first_proponent_age >= 80 OR second_proponent_age >= 80 OR third_proponent_age >= 80 OR forth_proponent_age >= 80) THEN 'Over 80 years old'
      ELSE 'Less than 80 years old'
    END AS proponent_age_classification,
    CASE
      WHEN (score_bigid > 0 OR
            score_bigid_first_proponent > 0 OR
            score_bigid_second_proponent > 0 OR
            score_bigid_third_proponent > 0 OR
            score_bigid_forth_proponent > 0 OR
            subjects_predictus_first_proponent <> 'NaN' OR
            subjects_predictus_second_proponent <> 'NaN' OR
            subjects_predictus_third_proponent <> 'NaN' OR
            subjects_predictus_forth_proponent <> 'NaN' OR
            predictus_status_message_first_proponent = 'OK' OR
            predictus_status_message_second_proponent = 'OK' OR
            predictus_status_message_third_proponent = 'OK' OR
            predictus_status_message_fourth_proponent = 'OK' OR
            located_processes_predictus = 'SIM') THEN 'Defendant in any legal proceeding'
      ELSE 'No relevant legal proceeding'
    END AS legal_proceedings,
    CASE
      WHEN (is_first_proponent_pep = TRUE OR is_second_proponent_pep = TRUE OR is_third_proponent_pep = TRUE OR is_forth_proponent_pep = TRUE) THEN 'PEP'
      ELSE 'Not PEP'
    END AS pep,
    CASE
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_criminal <> 'NaN') THEN bigid_process_details_criminal
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_criminal_first_proponent <> 'NaN') THEN bigid_process_details_criminal_first_proponent
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_criminal_second_proponent <> 'NaN') THEN bigid_process_details_criminal_second_proponent
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_criminal_third_proponent <> 'NaN') THEN bigid_process_details_criminal_third_proponent
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_criminal_forth_proponent <> 'NaN') THEN bigid_process_details_criminal_forth_proponent
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_civel <> 'NaN') THEN bigid_process_details_civel
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_civel_first_proponent <> 'NaN') THEN bigid_process_details_civel_first_proponent
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_civel_second_proponent <> 'NaN') THEN bigid_process_details_civel_second_proponent
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_civel_third_proponent <> 'NaN') THEN bigid_process_details_civel_third_proponent
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_civel_forth_proponent <> 'NaN') THEN bigid_process_details_civel_forth_proponent
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_tax <> 'NaN') THEN bigid_process_details_tax
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_tax_first_proponent <> 'NaN') THEN bigid_process_details_tax_first_proponent
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_tax_second_proponent <> 'NaN') THEN bigid_process_details_tax_second_proponent
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_tax_third_proponent <> 'NaN') THEN bigid_process_details_tax_third_proponent
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND bigid_process_details_tax_forth_proponent <> 'NaN') THEN bigid_process_details_tax_forth_proponent
      WHEN subjects_predictus_first_proponent <> 'NaN' THEN subjects_predictus_first_proponent
      WHEN subjects_predictus_second_proponent <> 'NaN' THEN subjects_predictus_second_proponent
      WHEN subjects_predictus_third_proponent <> 'NaN' THEN subjects_predictus_third_proponent
      WHEN subjects_predictus_forth_proponent <> 'NaN' THEN subjects_predictus_forth_proponent
      ELSE 'No relevant legal proceeding'
    END AS legal_proceedings_type,
    CASE
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND (subjects_predictus_first_proponent = 'NaN' AND subjects_predictus_second_proponent = 'NaN' AND subjects_predictus_third_proponent = 'NaN' AND subjects_predictus_forth_proponent = 'NaN' AND predictus_status_message_first_proponent <> 'OK' AND predictus_status_message_second_proponent <> 'OK' AND predictus_status_message_third_proponent <> 'OK' AND predictus_status_message_fourth_proponent <> 'OK' AND located_processes_predictus <> 'SIM')) THEN 'Only BigData'
      WHEN (((score_bigid IS NULL OR score_bigid  = 0) AND (score_bigid_first_proponent IS NULL OR score_bigid_first_proponent = 0) AND (score_bigid_second_proponent IS NULL OR score_bigid_second_proponent = 0) AND (score_bigid_third_proponent IS NULL OR score_bigid_third_proponent = 0) AND (score_bigid_forth_proponent IS NULL OR score_bigid_forth_proponent = 0)) AND (subjects_predictus_first_proponent <> 'NaN' OR subjects_predictus_second_proponent <> 'NaN' OR subjects_predictus_third_proponent <> 'NaN' OR subjects_predictus_forth_proponent <> 'NaN' OR predictus_status_message_first_proponent = 'OK' OR predictus_status_message_second_proponent = 'OK' OR predictus_status_message_third_proponent = 'OK' OR predictus_status_message_fourth_proponent = 'OK' OR located_processes_predictus = 'SIM')) THEN 'Only Predictus'
      WHEN ((score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0) AND (subjects_predictus_first_proponent <> 'NaN' OR subjects_predictus_second_proponent <> 'NaN' OR subjects_predictus_third_proponent <> 'NaN' OR subjects_predictus_forth_proponent <> 'NaN' OR predictus_status_message_first_proponent = 'OK' OR predictus_status_message_second_proponent = 'OK' OR predictus_status_message_third_proponent = 'OK' OR predictus_status_message_fourth_proponent = 'OK' OR located_processes_predictus = 'SIM')) THEN 'Both'
      ELSE 'No relevant legal proceeding'
    END AS legal_proceedings_share,
    CASE
      WHEN p.origin = 'PJ/company' THEN 'PJ'
      WHEN p.is_3p = TRUE THEN '3P'
      WHEN p.propose_status NOT IN ('Proposta Cancelada', 'Erro') AND p.origin = 'PF' AND c.proposal_number IS NULL THEN 'Error Neurotech Report'
      WHEN automatic_reproval_real_state_rs = 'NAO' THEN 'Rio Grande do Sul'
      WHEN proponents_count > 4 THEN 'More than 4 proponents'
      WHEN (rent_amount <> 'NaN' AND rent_amount < 600) THEN 'Rent less than 600 reais'
      WHEN (rent_amount <> 'NaN' AND rent_amount >= 15000) THEN 'Rent over 15.000 reais'
      WHEN (is_blocklist_document = TRUE OR ARRAY_CONTAINS(is_blocklist_document_list, TRUE)) THEN 'Blocklist'
      WHEN (is_document_federal = FALSE OR status_message_federal_first_proponent = 'NAO ENCONTRADO' OR status_message_federal_second_proponent = 'NAO ENCONTRADO' OR status_message_federal_third_proponent = 'NAO ENCONTRADO' OR status_message_federal_fourth_proponent = 'NAO ENCONTRADO') THEN 'CPF does not exist at the IRS'
      WHEN ((name_check_rating <> 'NaN' AND name_check_rating < 0.5) OR (array_min(name_check_rating_list) < 0.5)) THEN 'The name provided does not match the IRS'
      WHEN (is_minor_age_document = TRUE OR is_minor_age_document_list = TRUE OR smartgtwrf_message = 'DADOS_BLOQUEADOS_CPF_MENOR_DE_IDADE') THEN 'Under Age'
      WHEN (document_status_federal IN ('NULA', 'PENDENTE DE REGULARIZAÇÃO', 'SUSPENSA', 'CANCELADA', 'TITULAR FALECIDO') OR ARRAY_CONTAINS(document_status_federal_list, 'PENDENTE DE REGULARIZAÇÃO') OR ARRAY_CONTAINS(document_status_federal_list, 'NULA') OR ARRAY_CONTAINS(document_status_federal_list, 'SUSPENSA') OR ARRAY_CONTAINS(document_status_federal_list, 'CANCELADA') OR ARRAY_CONTAINS(document_status_federal_list, 'TITULAR FALECIDO') OR bigdataboost_document_status IN ('NULA', 'PENDENTE DE REGULARIZACAO', 'SUSPENSA', 'CANCELADA', 'TITULAR FALECIDO') OR ARRAY_CONTAINS(bigdataboost_document_status_list, 'PENDENTE DE REGULARIZACAO') OR ARRAY_CONTAINS(bigdataboost_document_status_list, 'NULA') OR ARRAY_CONTAINS(bigdataboost_document_status_list, 'SUSPENSA') OR ARRAY_CONTAINS(bigdataboost_document_status_list, 'CANCELADA') OR ARRAY_CONTAINS(bigdataboost_document_status_list, 'TITULAR FALECIDO')) THEN 'Irregular CPF'
      WHEN matchrate = 'SIM' THEN 'PEP with Sanction'
      WHEN ((analysis_result <> 'REPROVADO' AND ((ts_operation < cast('2025-02-13' as date) AND v3_model_score <> 'NaN') OR (ts_operation >= cast('2025-02-13' as date) AND v4_model_score <> 'NaN')) AND proposal_rating = 'NaN') OR status_bigdataboost = 'N') THEN 'Error Neurotech Flow'
      WHEN ((ts_operation >= cast('2024-04-24' as date) AND (score_bigid > 0 OR score_bigid_first_proponent > 0 OR score_bigid_second_proponent > 0 OR score_bigid_third_proponent > 0 OR score_bigid_forth_proponent > 0)) OR subjects_predictus_first_proponent <> 'NaN' OR subjects_predictus_second_proponent <> 'NaN' OR subjects_predictus_third_proponent <> 'NaN' OR subjects_predictus_forth_proponent <> 'NaN' OR predictus_status_message_first_proponent = 'OK' OR predictus_status_message_second_proponent = 'OK' OR predictus_status_message_third_proponent = 'OK' OR predictus_status_message_fourth_proponent = 'OK' OR located_processes_predictus = 'SIM') THEN 'Legal Proceeding'
      WHEN p.propose_status IN ('Proposta Cancelada', 'Erro') THEN 'Propose Cancelled/Error'
      ELSE NULL
    END AS reason_missing,
    CASE
      WHEN analysis_result = 'REPROVADO' OR analysis_result IS NULL OR proposal_rating = 'NaN' THEN 'No Information'
      WHEN (refin_pefin_occurrence_type IN ('PENDENCIA FINANCEIRA', 'PENDENCIA FINANCEIRA#@#REFIN', 'REFIN') OR ARRAY_CONTAINS(refin_pefin_occurrence_type_list,'PENDENCIA FINANCEIRA') OR ARRAY_CONTAINS(refin_pefin_occurrence_type_list,'REFIN') OR protest_amount > 0 OR array_min(protest_amount_list) > 0 OR array_max(protest_amount_list) > 0) THEN 'Indebted'
      ELSE 'Not Indebted'
    END AS indebted,
    c.main_proponent_name,
    c.main_proponent_email,
    c.proposal_cpfs AS proponents_cpf,
    reason_document_on_blocklist_list,
    name_check_rating,
    name_check_rating_list,
    is_blocklist_document_list,
    serasa_income,
    transunion_income,
    proposal_declared_income,
    is_foreign_document,
    is_foreign_document_list,
    is_minor_age_document,
    is_minor_age_document_list,
    IF(ROW_NUMBER() OVER (PARTITION BY c.proposal_number ORDER BY c.ts_operation DESC) = 1, TRUE, FALSE) AS is_last_register,
    min_date.ts_begin AS dt_propose,
    IF(c.log_result != 'RESSUBMISSAO', c.ts_inserted, LAG(CAST(c.ts_inserted AS TIMESTAMP)) OVER (PARTITION BY c.proposal_number ORDER BY c.ts_inserted)) AS ts_begin,
    c.ts_inserted,
    c.ts_dh_processed AS ts_end,
    c.ts_operation
FROM
    datalake_velo_neurotech_clean.logs_credit_granting c
LEFT JOIN(
    SELECT
        proposal_number,
        MIN(DATE(ts_inserted)) AS ts_begin
        FROM datalake_velo_neurotech_clean.logs_credit_granting
        GROUP BY 1
    ) AS min_date
    ON min_date.proposal_number = c.proposal_number
LEFT JOIN
    datalake_velo.propose p
    ON p.id_propose = c.proposal_number
WHERE
    c.proposal_number IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY c.ts_inserted ORDER BY c.ts_dh_processed) = 1
