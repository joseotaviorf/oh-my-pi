WITH backtest AS (
  SELECT 
    CAST(id_proposal AS INTEGER) AS id_proposal,
    CAST(NULL AS INTEGER) AS id_proponent,
    REPLACE(REPLACE(cpf,".",""),"-","") AS cpf,
    CAST(estimated_income_neoway_low AS DOUBLE) AS neoway_estimated_income_low,
    CAST(estimated_income_neoway_midpoint AS DOUBLE) AS neoway_estimated_income_midpoint,
    CAST(estimated_income_neoway_upper AS DOUBLE) AS neoway_estimated_income_upper
  FROM 
    datalake_static_files_raw.bureaus_neoway_historical_raw    
  WHERE
    cpf IS NOT NULL
),

income_report_data AS (
  SELECT
    p.cpf,
    r.ts_created AS timestamp,
    MAX(GET_JSON_OBJECT(p.attributes, "$.incomeRangeLowerValue")) AS neoway_lower_value,
    MAX(COALESCE(GET_JSON_OBJECT(p.attributes, "$.incomeRangeHigherValue"), 19080)) AS neoway_upper_value
  FROM
    datalake_arquivo_confidencial_clean.presumed_income_report_aud AS p
  JOIN
    datalake_arquivo_confidencial_clean.rev_info AS r
      ON p.rev = r.rev
  WHERE
    source = 'NEOWAY'
  GROUP BY
    p.cpf, r.ts_created
),

last_credit_analysis AS (
  SELECT
    id_proposal,
    MAX(ts_created) AS last_ca_timestamp
  FROM
    datalake_sorting_hat_clean.credit_analysis 
  GROUP BY id_proposal
),

enriched_income_report_data AS (
  SELECT DISTINCT
    l_ca.id_proposal,
    ppt.id AS id_proponent,
    ppt.cpf,
    ir.neoway_lower_value,
    ir.neoway_upper_value,
    ir.timestamp,
    l_ca.last_ca_timestamp,
    MAX(ir.timestamp) OVER(PARTITION BY pps.id, ppt.id, ppt.cpf) AS ir_last_timestamp
  FROM
    datalake_sorting_hat_clean.proposal AS pps
  JOIN
    datalake_sorting_hat_clean.proponent AS ppt
      ON pps.id = ppt.id_proposal
  JOIN
    last_credit_analysis AS l_ca
      ON pps.id = l_ca.id_proposal
  JOIN
    income_report_data AS ir
      ON ir.cpf = REPLACE(REPLACE(ppt.cpf,".",""),"-","")
      AND ir.timestamp <= l_ca.last_ca_timestamp
),

internal_data AS (
  SELECT
    REPLACE(REPLACE(cpf,".",""),"-","") AS cpf,
    id_proposal,
    id_proponent,
    CAST(neoway_lower_value AS DOUBLE) AS neoway_estimated_income_low,
    (CAST(neoway_lower_value AS DOUBLE) + CAST(neoway_upper_value AS DOUBLE))/2 AS neoway_estimated_income_midpoint,
    CAST(neoway_upper_value AS DOUBLE) AS neoway_estimated_income_upper
  FROM 
    enriched_income_report_data
  WHERE 
    timestamp = ir_last_timestamp
    AND DATEDIFF(last_ca_timestamp, ir_last_timestamp) < 30
)

SELECT
  COALESCE(btest.id_proposal, idata.id_proposal) AS id_proposal,
  COALESCE(btest.id_proponent, idata.id_proponent) AS id_proponent,
  COALESCE(btest.cpf, idata.cpf) AS cpf,
  COALESCE(btest.neoway_estimated_income_low, idata.neoway_estimated_income_low) AS neoway_estimated_income_low,
  COALESCE(btest.neoway_estimated_income_midpoint, idata.neoway_estimated_income_midpoint) AS neoway_estimated_income_midpoint,
  COALESCE(btest.neoway_estimated_income_upper, idata.neoway_estimated_income_upper) AS neoway_estimated_income_upper
FROM
  backtest btest
  FULL OUTER JOIN
    internal_data AS idata
      ON btest.id_proposal = idata.id_proposal
      AND btest.cpf = idata.cpf