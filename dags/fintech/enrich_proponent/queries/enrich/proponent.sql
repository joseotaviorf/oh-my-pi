WITH last_credit_evaluation AS (
  SELECT DISTINCT
    id_proposal,
    FIRST(id) OVER (PARTITION BY id_proposal ORDER BY ts_updated desc) AS id_credit_evaluation
  FROM
    datalake_docx_clean.credit_evaluation
),
integration_pre_table AS (
  SELECT
    cpf,
    rb.ts_created ts_begin,
    re.ts_created ts_end,
    SUM(GET_JSON_OBJECT(attributes, '$.score')) FILTER (WHERE  integration_provider = 'SERASA_SCORE_CSBA') csba_score,
    SUM(GET_JSON_OBJECT(attributes, '$.score')) FILTER (WHERE  integration_provider = 'SERASA_SCORE_HSPI') hspi_score,
    SUM(GET_JSON_OBJECT(attributes, '$.score')) FILTER (WHERE  integration_provider = 'BOAVISTA_SCORE_CSR60') old_bv_score,
    SUM(GET_JSON_OBJECT(attributes, '$.positive_score_p4')) FILTER (WHERE  integration_provider = 'BOAVISTA_SCORE_PACKAGE_1') bv_positive_score,
    MAX(GET_JSON_OBJECT(raw_data, '$.analysis_output.scr.scr_data[0].operation_items')) FILTER (WHERE  integration_provider = 'QI_TECH_SCR') scr_mob1_operation_data
  FROM
    datalake_arquivo_confidencial_clean.integration_report_aud AS ira
  JOIN
    datalake_arquivo_confidencial_clean.rev_info AS rb
      ON rb.rev = ira.rev
  LEFT JOIN
    datalake_arquivo_confidencial_clean.rev_info AS re
      ON re.rev = ira.rev_end
  WHERE
    integration_provider IN ('SERASA_SCORE_CSBA', 'SERASA_SCORE_HSPI', 'BOAVISTA_SCORE_CSR60', 'BOAVISTA_SCORE_PACKAGE_1', 'QI_TECH_SCR')
  GROUP BY 1,2,3
), bigid  AS  (
SELECT
    cpf,
    rb.ts_created ts_begin,
    LEAD(rb.ts_created) OVER (PARTITION BY cpf ORDER BY ira.rev) AS ts_end,
    GET_JSON_OBJECT(attributes, '$.score') big_id_score
FROM
  datalake_arquivo_confidencial_clean.integration_report_aud AS ira
JOIN
  datalake_arquivo_confidencial_clean.rev_info rb ON rb.rev = ira.rev
WHERE integration_provider = 'BIGID_BACKGROUND_CHECK'
) , documentation_report  AS  (  /*IDwaall*/
SELECT DISTINCT
    cpf,
    id_proposal,
    ts_created ts_created,
    status AS report_status,
    matrix_name AS matrix_name,
    report_result AS report_result,
    validations AS report_validations,
    row_number() OVER w AS rn
FROM datalake_arquivo_confidencial_clean.documentation_report
WINDOW w AS (PARTITION BY cpf,id_proposal ORDER BY ts_updated DESC)
), bureaus_table AS (
SELECT /*+ RANGE_JOIN(ipt, 6732435) */
    pp.cpf,
    pp.id_proposal,
    MAX(COALESCE(pp.serasa_score, ipt.csba_score)) AS csba_score,
    MAX(COALESCE(pp.boavista_score, ipt.old_bv_score)) AS bv_score,
    MAX(ipt.hspi_score) AS hspi_score,
    MAX(ipt.bv_positive_score) AS boavista_positive_score,
    MAX(ipt.scr_mob1_operation_data) AS scr_mob1_operation_data,
    MAX(income_nature) AS income_nature,
    MAX(lower(email)) AS email,
    MAX(is_going_to_reside) AS is_going_to_reside,
    MAX(location_motive) AS location_motive,
    MAX(extra_income_origin) AS extra_income_origin,
    MAX(extra_income_value) AS extra_income_value
FROM
  datalake_sorting_hat_clean.proponent AS pp
JOIN
  datalake_sorting_hat_clean.proposal AS ps
    ON ps.id = pp.id_proposal
LEFT JOIN
  integration_pre_table AS ipt
    ON ipt.cpf = REPLACE(REPLACE(pp.cpf, '.', ''), '-','') AND ps.ts_created BETWEEN ipt.ts_begin AND COALESCE(ipt.ts_end,current_date)
GROUP BY 1,2
), cpf_folder_reference AS (
SELECT
    fr.id,
    MAX(GET_JSON_OBJECT(attributes, '$.cpf')) AS cpf
FROM
  datalake_docx_clean.document d
JOIN
  datalake_docx_clean.folder_reference AS fr
    ON fr.id_source_folder = d.id_folder
WHERE fr.id_folder_reference_type = 7
GROUP BY 1
), unico AS (
SELECT
     GET_JSON_OBJECT(reference_properties, '$.proposalId') id_proposal,
     fr.id  AS  id_folder_reference,
     cfr.cpf,
     ucp.*,
     row_number() OVER (PARTITION BY GET_JSON_OBJECT(reference_properties, '$.proposalId'), cfr.cpf ORDER BY ucp.ts_updated) rn
FROM
  datalake_docx_clean.folder f
JOIN
  datalake_docx_clean.folder_reference AS fr
    ON fr.id_source_folder = f.id
JOIN
  datalake_arquivo_confidencial_clean.unico_check_process AS ucp
    ON ucp.id_external = f.id
LEFT JOIN
  cpf_folder_reference AS cfr
    ON cfr.id = fr.id
WHERE fr.id_folder_reference_type = 7
), email_age AS (
SELECT
    LOWER(email) AS email,
    rb.ts_created AS ts_begin,
    LEAD(rb.ts_created) OVER (PARTITION BY LOWER(email) ORDER BY era.rev) AS ts_end,
    score
FROM
  datalake_arquivo_confidencial_clean.emailage_result_aud AS era
JOIN
  datalake_arquivo_confidencial_clean.rev_info AS rb
    ON rb.rev = era.rev
LEFT JOIN
  datalake_arquivo_confidencial_clean.rev_info AS re
    ON re.rev = era.rev_end
),
sorting_hat_proponent AS (
SELECT 
  cpf,
  id_proposal,
  MAX(id) AS id_proponent_sorting_hat
FROM datalake_sorting_hat_clean.proponent
GROUP BY 1,2
),
ebdb_proponent AS (
SELECT 
   id_proposal,
   cpf,
   MAX(id) AS id_proponent_ebdb
FROM datalake_ebdb_clean.proponent_proposal
WHERE type='Inquilino'
GROUP BY 1,2
)
SELECT /*+ RANGE_JOIN(bigid, 9123) */
    MD5(CONCAT(cep.cpf,'|', lce.id_proposal)) AS id_proponent,
    cep.id AS id_proponent_docx,
    shp.id_proponent_sorting_hat,
    epp.id_proponent_ebdb,
    cep.cpf,
    cep.name,
    lce.id_proposal,
    cep.monthly_income,
    cep.occupation_area,
    bt.is_going_to_reside,
    bt.csba_score AS serasa_csba_score,
    bt.hspi_score AS serasa_hspi_socre,
    bt.bv_score AS boavista_old_score,
    bt.boavista_positive_score,
    bt.scr_mob1_operation_data,
    bigid.big_id_score AS big_id_score,
    unico.score AS unico_score,
    unico.status AS unico_status,
    unico.has_biometry AS has_biometry_unico,
    unico.liveness AS unico_liveness,
    unico.face_match AS unico_face_match,
    dr.matrix_name AS idwall_matrix_name,
    dr.report_result AS idwall_report_result,
    dr.report_status AS idwall_report_status,
    ea.email AS emailage_email,
    ea.score AS emailage_score,
    IF(cep.proponent_type='USER',TRUE,FALSE) is_main_proponent
FROM
  last_credit_evaluation AS lce
JOIN
  datalake_docx_clean.credit_evaluation_proponent AS cep
    ON lce.id_credit_evaluation = cep.id_credit_evaluation
LEFT JOIN
  sorting_hat_proponent AS shp
    ON shp.id_proposal = lce.id_proposal AND shp.cpf = cep.cpf
LEFT JOIN 
  ebdb_proponent AS epp
    ON epp.id_proposal = lce.id_proposal AND epp.cpf = cep.cpf
LEFT JOIN
  bureaus_table AS bt
    ON bt.cpf = cep.cpf AND bt.id_proposal = lce.id_proposal
LEFT JOIN
  unico
    ON unico.id_proposal = lce.id_proposal AND unico.cpf = cep.cpf AND unico.rn = 1
LEFT JOIN
  datalake_ebdb_clean.proposal AS ep
    ON ep.id = lce.id_proposal
LEFT JOIN
  bigid
    ON bigid.cpf = REPLACE(REPLACE(cep.cpf, '.', ''), '-','') AND (ep.ts_documentation_sent + INTERVAL '2' HOUR) BETWEEN bigid.ts_begin AND COALESCE(bigid.ts_end, current_date)
LEFT JOIN
  email_age AS ea
    ON ea.email = bt.email AND (ep.ts_documentation_sent + INTERVAL '2' HOUR) BETWEEN ea.ts_begin AND COALESCE(ea.ts_end,current_date)
LEFT JOIN
  documentation_report AS dr
    ON dr.id_proposal = lce.id_proposal AND dr.cpf = cep.cpf AND dr.rn = 1