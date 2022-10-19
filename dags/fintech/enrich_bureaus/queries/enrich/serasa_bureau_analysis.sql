WITH backtest AS (
  SELECT
    id_proposal,
    id_proponent, 
    CAST(REPLACE(REPLACE(cpf,".",""),"-","") AS BIGINT) AS cpf,
    CAST(SCORE_CSBA AS FLOAT) AS serasa_score_csba,
    CAST(SCORE_HSPN AS FLOAT) AS serasa_score_hspn
  FROM
    datalake_static_files_raw.bureaus_serasa_historical_raw
),

integration_report_data AS (
  SELECT
    CAST(REPLACE(REPLACE(cpf,".",""),"-","") AS BIGINT) AS cpf,
    integration_provider,
    CASE
      WHEN integration_provider = 'SERASA_SCORE_HSPI' THEN GET_JSON_OBJECT(attributes, "$.score")
    END AS serasa_score_hspn,
    CASE
      WHEN integration_provider = 'SERASA_SCORE_CSBA' THEN GET_JSON_OBJECT(attributes, "$.score")
    END AS serasa_score_csba,
    revinfo.ts_created AS timestamp
  FROM 
    datalake_arquivo_confidencial_clean.integration_report_aud AS itr
  JOIN
    datalake_arquivo_confidencial_clean.rev_info AS revinfo
      ON itr.rev = revinfo.rev
  WHERE
    integration_provider IN ('SERASA_SCORE_HSPI', 'SERASA_SCORE_CSBA')
    AND GET_JSON_OBJECT(attributes, "$.restrictedData") = False
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
    MAX(itr.timestamp) OVER(PARTITION BY l_ca.id_proposal, ppt.id, ppt.cpf, itr.integration_provider) AS max_itr_timestamp
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
),

integration_report_csba_data AS (
  SELECT
    id_proposal,
    id_proponent,
    cpf,
    CAST(serasa_score_csba AS FLOAT) AS serasa_score_csba
  FROM 
    enriched_integration_report_data
  WHERE
    max_itr_timestamp = timestamp
    AND DATEDIFF(last_ca_timestamp, max_itr_timestamp) < 30
    AND integration_provider = 'SERASA_SCORE_CSBA'
),

sorting_hat_csba_data AS (
  SELECT DISTINCT
    id_proposal,
    id AS id_proponent,
    CAST(REPLACE(REPLACE(cpf,".",""),"-","") AS BIGINT) AS cpf,
    serasa_score AS serasa_score_csba
  FROM
    datalake_sorting_hat_clean.proponent
),

internal_csba_data AS (
  SELECT
    COALESCE(itr.id_proposal, sh.id_proposal) AS id_proposal,
    COALESCE(itr.id_proponent, sh.id_proponent) AS id_proponent,
    COALESCE(itr.cpf, sh.cpf) AS cpf,
    COALESCE(sh.serasa_score_csba, itr.serasa_score_csba) AS serasa_score_csba
  FROM
    integration_report_csba_data itr
  FULL OUTER JOIN
    sorting_hat_csba_data sh
      ON itr.id_proposal = sh.id_proposal
      AND itr.id_proponent = sh.id_proponent
      AND itr.cpf = sh.cpf
),

internal_hspn_data AS (
  SELECT
    id_proposal,
    id_proponent,
    cpf,
    CAST(serasa_score_hspn AS FLOAT) AS serasa_score_hspn
  FROM 
    enriched_integration_report_data
  WHERE
    max_itr_timestamp = timestamp
    AND DATEDIFF(last_ca_timestamp, max_itr_timestamp) < 30
    AND integration_provider = 'SERASA_SCORE_HSPI'
    AND serasa_score_hspn >= 0
),

internal_data AS (
  SELECT
    COALESCE(csba.id_proposal, hspn.id_proposal) AS id_proposal,
    COALESCE(csba.id_proponent, hspn.id_proponent) AS id_proponent,
    COALESCE(csba.cpf, hspn.cpf) AS cpf,
    serasa_score_csba,
    serasa_score_hspn
  FROM 
    internal_csba_data AS csba
    FULL OUTER JOIN 
      internal_hspn_data AS hspn
        ON csba.id_proposal = hspn.id_proposal 
        AND csba.id_proponent = hspn.id_proponent 
        AND csba.cpf = hspn.cpf
  WHERE
    csba.id_proposal IS NOT NULL
    AND csba.id_proponent IS NOT NULL
    AND csba.cpf IS NOT NULL
)

SELECT
  COALESCE(btest.id_proposal, idata.id_proposal) AS id_proposal,
  COALESCE(btest.id_proponent, idata.id_proponent) AS id_proponent,
  COALESCE(btest.cpf, idata.cpf) AS cpf,
  COALESCE(btest.serasa_score_csba, idata.serasa_score_csba) AS serasa_score_csba,
  COALESCE(btest.serasa_score_hspn, idata.serasa_score_hspn) AS serasa_score_hspn
FROM
  backtest btest
  FULL OUTER JOIN
    internal_data AS idata
      ON btest.id_proposal = idata.id_proposal
      AND btest.id_proponent = idata.id_proponent
      AND btest.cpf = idata.cpf