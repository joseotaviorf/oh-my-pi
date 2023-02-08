WITH integration_report_data AS (
  SELECT
    CAST(REPLACE(REPLACE(cpf,".",""),"-","") AS BIGINT) AS cpf,
    GET_JSON_OBJECT(attributes, "$.score") AS boavista_score,
    revinfo.ts_created AS timestamp
  FROM
    datalake_arquivo_confidencial_clean.integration_report_aud AS itr
  JOIN
    datalake_arquivo_confidencial_clean.rev_info AS revinfo
      ON itr.rev = revinfo.rev
  WHERE
    integration_provider = 'BOAVISTA_SCORE_CSR60'
    AND GET_JSON_OBJECT(attributes, "$.restrictedData") = False
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

arq_conf_data AS (
  SELECT
    id_proposal,
    id_proponent,
    cpf,
    CAST(boavista_score AS FLOAT) AS boavista_score
  FROM
    enriched_integration_report_data
  WHERE
    max_itr_timestamp = timestamp
    AND DATEDIFF(last_ca_timestamp, max_itr_timestamp) <= 30
),

sorting_hat_data AS (
  SELECT
    id_proposal,
    id AS id_proponent,
    CAST(REPLACE(REPLACE(cpf,".",""),"-","") AS BIGINT) AS cpf,
    boavista_score
  FROM
    datalake_sorting_hat_clean.proponent
)

SELECT
  COALESCE(arq.id_proposal, sh.id_proposal) AS id_proposal,
  COALESCE(arq.id_proponent, sh.id_proponent) AS id_proponent,
  COALESCE(arq.cpf, sh.cpf) AS cpf,
  COALESCE(sh.boavista_score, arq.boavista_score) AS boavista_score
FROM
  arq_conf_data arq
FULL OUTER JOIN
  sorting_hat_data sh
    ON arq.id_proposal = sh.id_proposal
    AND arq.id_proponent = sh.id_proponent
    AND arq.cpf = sh.cpf
WHERE
  sh.id_proponent IS NOT NULL
  AND sh.id_proposal IS NOT NULL
  AND sh.cpf IS NOT NULL
