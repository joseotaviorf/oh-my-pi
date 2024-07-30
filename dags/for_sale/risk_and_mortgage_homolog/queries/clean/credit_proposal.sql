SELECT
  id,
  credit_proposal_id AS id_credit_proposal,
  credit_letter_document_id AS id_credit_letter_document,
  offer_pre_analysis_id AS id_offer_pre_analysis,
  bank,
  credit_letter_file_name,
  status,
  accepted AS is_accepted,
  credit_start_date AS dt_credit_started,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_risk_and_mortgage_homolog_raw.credit_proposal
WHERE
  MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
