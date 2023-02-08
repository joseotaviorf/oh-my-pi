WITH backtest AS (
  SELECT
    id_proposal,
    id_proponent,
    CAST(REPLACE(REPLACE(cpf,".",""),"-","") AS BIGINT) AS cpf,
    renda_presumida AS transunion_presumed_income
  FROM
    datalake_static_files_raw.bureaus_transunion_historical_raw
),

income_report_data AS (
  SELECT
    CAST(REPLACE(REPLACE(p.cpf,".",""),"-","") AS BIGINT) AS cpf,
    r.ts_created AS timestamp,
    MAX(presumed_income) AS transunion_presumed_income
  FROM
    datalake_arquivo_confidencial_clean.presumed_income_report_aud AS p
  JOIN
    datalake_arquivo_confidencial_clean.rev_info AS r
      ON p.rev = r.rev
  WHERE
    source = 'CRIVO'
  GROUP BY
    1, 2
),

last_credit_analysis AS (
  SELECT
    id_proposal,
    MAX(issued_at) AS last_ca_timestamp
  FROM
    datalake_sorting_hat_clean.screening_result_version sr
    JOIN datalake_sorting_hat_raw.transaction t
      ON sr.id_transaction = t.id
  GROUP BY id_proposal
),

enriched_income_report_data AS (
  SELECT DISTINCT
    l_ca.id_proposal,
    ppt.id AS id_proponent,
    CAST(REPLACE(REPLACE(ppt.cpf,".",""),"-","") AS BIGINT) AS cpf,
    ir.transunion_presumed_income,
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
      ON ir.cpf = CAST(REPLACE(REPLACE(ppt.cpf,".",""),"-","") AS BIGINT)
      AND ir.timestamp <= l_ca.last_ca_timestamp
),

internal_data AS (
  SELECT
    REPLACE(REPLACE(cpf,".",""),"-","") AS cpf,
    id_proposal,
    id_proponent,
    transunion_presumed_income
  FROM
    enriched_income_report_data
  WHERE
    timestamp = ir_last_timestamp
    AND DATEDIFF(last_ca_timestamp, ir_last_timestamp) <= 30
)

SELECT
  COALESCE(btest.id_proposal, idata.id_proposal) AS id_proposal,
  COALESCE(btest.id_proponent, idata.id_proponent) AS id_proponent,
  COALESCE(btest.cpf, idata.cpf) AS cpf,
  COALESCE(btest.transunion_presumed_income, idata.transunion_presumed_income) AS transunion_presumed_income
FROM
  backtest btest
  FULL OUTER JOIN
    internal_data AS idata
      ON btest.id_proposal = idata.id_proposal
      AND btest.id_proponent = idata.id_proponent
      AND btest.cpf = idata.cpf
