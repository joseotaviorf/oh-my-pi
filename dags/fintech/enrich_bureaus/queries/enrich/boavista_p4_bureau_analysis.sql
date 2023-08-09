WITH
backtest AS (
  SELECT
    bvs.id_proposal,
    CAST(REPLACE(REPLACE(bvs.cpf,".",""),"-","") AS BIGINT) AS cpf,
    CAST(bvs.score_p4 AS FLOAT) AS boavista_score_p4,
    CAST(bvs.negative_score AS FLOAT) AS boavista_negative_score
  FROM
    datalake_static_files_raw.bureaus_boavista_historical_backtest_2022_raw bvs
),

clean_backtest AS (
  SELECT
    bt.id_proposal,
    ppt.id as id_proponent,
    bt.cpf,
    CASE
      WHEN boavista_score_p4 = 1 THEN NULL
      ELSE boavista_score_p4
    END AS boavista_score_p4,
    bt.boavista_negative_score
  FROM
    backtest as bt
  JOIN
    datalake_sorting_hat_clean.proponent AS ppt
      ON bt.cpf = CAST(REPLACE(REPLACE(ppt.cpf,".",""),"-","") AS BIGINT)
),

integration_report_data AS (
  SELECT
    CAST(REPLACE(REPLACE(cpf,".",""),"-","") AS BIGINT) AS cpf,
    GET_JSON_OBJECT(attributes, "$.negative_score") AS boavista_negative_score,
    GET_JSON_OBJECT(attributes, "$.score_p4") AS boavista_score_p4,
    revinfo.ts_created AS timestamp

  FROM
    datalake_arquivo_confidencial_clean.integration_report_aud AS itr
  JOIN
    datalake_arquivo_confidencial_clean.rev_info AS revinfo
      ON itr.rev = revinfo.rev
  WHERE
    integration_provider = 'BOAVISTA_SCORE_PACKAGE_1'
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
),

production_data AS (
  SELECT
    id_proposal,
    id_proponent,
    cpf,
    CAST(boavista_score_p4 AS FLOAT) AS boavista_score_p4,
    CAST(boavista_negative_score AS FLOAT) AS boavista_negative_score
  FROM
    enriched_integration_report_data
  WHERE
    max_itr_timestamp = timestamp
    AND DATEDIFF(last_ca_timestamp, max_itr_timestamp) <= 30
)

SELECT
  COALESCE(btest.id_proposal, pdata.id_proposal) AS id_proposal,
  COALESCE(btest.id_proponent, pdata.id_proponent) AS id_proponent,
  COALESCE(btest.cpf, pdata.cpf) AS cpf,
  COALESCE(btest.boavista_score_p4, pdata.boavista_score_p4) AS boavista_score_p4,
  COALESCE(btest.boavista_negative_score, pdata.boavista_negative_score) AS boavista_negative_score
FROM
  clean_backtest btest
  FULL OUTER JOIN
    production_data AS pdata
      ON btest.id_proposal = pdata.id_proposal
      AND btest.id_proponent = pdata.id_proponent
      AND btest.cpf = pdata.cpf

WHERE
  COALESCE(btest.id_proposal, pdata.id_proposal) IS NOT NULL
  AND COALESCE(btest.id_proponent, pdata.id_proponent) IS NOT NULL
  AND COALESCE(btest.cpf, pdata.cpf) IS NOT NULL
