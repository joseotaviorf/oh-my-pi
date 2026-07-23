WITH get_proposal_extraction_results AS (
  SELECT
    id_proposal,
    processing_result,
    COALESCE(error_type, processing_errors) AS error_type,
    number_of_errors,
    avg_net_income,
    median_net_income,
    avg_gross_income,
    median_gross_income,
    IF(processing_result = 'SUCCESS', 1, 0) AS is_processing_result_success,
    IF(processing_result = 'PARTIAL_SUCCESS', 1, 0) AS is_processing_result_partial_success,
    IF(processing_result = 'FAILURE', 1, 0) AS is_processing_result_failure,
    IF(documents_type = 'PAYSLIP', 1, 0) AS is_document_payslip,
    IF(documents_type = 'BANK_STATEMENT', 1, 0) AS is_document_bank_statement,
    IF(is_suspicious = TRUE, 1, 0) AS is_suspicious,
    ts_created
  FROM
    datalake_docpilot.income_extraction_processing
),
get_proposal_extraction_summary AS (
  SELECT
    id_proposal,
    CASE
      WHEN SUM(is_document_payslip) > 0 AND SUM(is_document_bank_statement) = 0 THEN 'PAYSLIP'
      WHEN SUM(is_document_payslip) = 0 AND SUM(is_document_bank_statement) > 0 THEN 'BANK_STATEMENT'
      WHEN SUM(is_document_payslip) > 0 AND SUM(is_document_bank_statement) > 0 THEN 'HYBRID'
    END AS proposal_documents_type,
    CASE
      WHEN SUM(is_processing_result_success) > 0 AND SUM(is_processing_result_partial_success) = 0 AND SUM(is_processing_result_failure) = 0 THEN 'SUCCESS'
      WHEN SUM(is_processing_result_success) > 0 AND (SUM(is_processing_result_partial_success) > 0 OR SUM(is_processing_result_failure) > 0) THEN 'PARTIAL_SUCCESS'
      WHEN SUM(is_processing_result_success) = 0 AND SUM(is_processing_result_partial_success) > 0 THEN 'PARTIAL_SUCCESS'
      WHEN SUM(is_processing_result_success) = 0 AND SUM(is_processing_result_partial_success) = 0 AND SUM(is_processing_result_failure) > 0 THEN 'FAILURE'
    END AS proposal_processing_result,
    ARRAY_JOIN(ARRAY_SORT(ARRAY_DISTINCT(ARRAY_AGG(error_type))), ', ') AS all_errors,
    SUM(number_of_errors) AS proposal_number_of_errors,
    COUNT(distinct error_type) AS proposal_number_of_distinct_errors,
    SUM(avg_net_income) AS proposal_sum_of_avg_net_income,
    SUM(median_net_income) AS proposal_sum_of_median_net_income,
    SUM(avg_gross_income) AS proposal_sum_of_avg_gross_income,
    SUM(median_gross_income) AS proposal_sum_of_median_gross_income,
    SUM(is_processing_result_success)  AS proposal_number_of_processing_result_success,
    SUM(is_processing_result_partial_success)  AS proposal_number_of_processing_result_partial_success,
    SUM(is_processing_result_failure) AS proposal_number_of_processing_result_failure,
    SUM(is_document_payslip) AS proposal_number_of_payslip,
    SUM(is_document_bank_statement) AS proposal_number_of_bank_statement,
    SUM(is_suspicious) AS proposal_number_of_suspicious_documents,
    MAX(ts_created) AS ts_proposal_last_income_extraction_result
  FROM
    get_proposal_extraction_results
  GROUP BY
    id_proposal
)
  SELECT
    id_proposal,
    proposal_number_of_errors,
    proposal_number_of_distinct_errors,
    all_errors AS proposal_errors,
    proposal_documents_type,
    proposal_processing_result,
    proposal_sum_of_avg_net_income,
    proposal_sum_of_median_net_income,
    proposal_sum_of_avg_gross_income,
    proposal_sum_of_median_gross_income,
    proposal_number_of_processing_result_success,
    proposal_number_of_processing_result_partial_success,
    proposal_number_of_processing_result_failure,
    proposal_number_of_bank_statement,
    proposal_number_of_payslip,
    proposal_number_of_suspicious_documents,
    ts_proposal_last_income_extraction_result,
    NOW() AS ts_updated
  FROM
    get_proposal_extraction_summary
