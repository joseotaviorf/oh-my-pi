WITH backtest AS (
  SELECT
    id_proposal,
    id_proponent,
    LPAD(CAST(cpf AS STRING), 11, '0') AS cpf,
    CAST(people_personal_relat__quantidade_de_relacionamentos AS INTEGER) AS bigdatacorp_total_relationships,
    CAST(people_dados_basicos__idade AS INTEGER) AS bigdatacorp_age,
    CAST(people_personal_relat__quantidade_de_conjuges AS INTEGER) AS bigdatacorp_total_spouses,
    CAST(people_personal_relat__quantidade_de_pessoas_no_household AS INTEGER) AS bigdatacorp_total_household,
    CAST(people_personal_relat__quantidade_de_socios AS INTEGER) AS bigdatacorp_total_partners
  FROM
    datalake_static_files_raw.bureaus_bigdatacorp_historical_raw
),

integration_report_data AS (
  SELECT
    cpf,
    CASE 
      WHEN integration_provider = 'BIGDATACORP_BASIC_DATA' THEN 'basic_data'
      WHEN integration_provider = 'BIGDATACORP_RELATED_PEOPLE' THEN 'related_people'
    END AS bigdatacorp_integration_type,
    GET_JSON_OBJECT(attributes, "$.Age") AS bigdatacorp_age,
    GET_JSON_OBJECT(attributes, "$.TotalSpouses") AS bigdatacorp_total_spouses,
    GET_JSON_OBJECT(attributes, "$.TotalPartners") AS bigdatacorp_total_partners,
    GET_JSON_OBJECT(attributes, "$.TotalCoworkers") AS bigdatacorp_total_household,
    GET_JSON_OBJECT(attributes, "$.TotalRelationships") AS bigdatacorp_total_relationships,
    revinfo.ts_created AS timestamp
  FROM 
    datalake_arquivo_confidencial_clean.integration_report_aud AS itr
  JOIN
    datalake_arquivo_confidencial_clean.rev_info AS revinfo
      ON itr.rev = revinfo.rev
  WHERE
    integration_provider IN ('BIGDATACORP_BASIC_DATA', 'BIGDATACORP_RELATED_PEOPLE')
    AND GET_JSON_OBJECT(attributes, "$.successCode") = True
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
    MAX(itr.timestamp) OVER(PARTITION BY l_ca.id_proposal, ppt.id, ppt.cpf, itr.bigdatacorp_integration_type) AS max_itr_timestamp
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
        ON itr.cpf = REPLACE(REPLACE(ppt.cpf,".",""),"-","")
        AND itr.timestamp < l_ca.last_ca_timestamp
),

internal_basic_data AS (
  SELECT
    id_proposal,
    id_proponent,
    cpf,
    CAST(bigdatacorp_age AS FLOAT) AS bigdatacorp_age
  FROM 
    enriched_integration_report_data
  WHERE
    max_itr_timestamp = timestamp
    AND DATEDIFF(last_ca_timestamp, max_itr_timestamp) < 30
    AND bigdatacorp_integration_type = 'basic_data'
),

internal_personal_data AS (
  SELECT
    id_proposal,
    id_proponent,
    cpf,
    CAST(bigdatacorp_total_spouses AS FLOAT) AS bigdatacorp_total_spouses,
    CAST(bigdatacorp_total_partners AS FLOAT) AS bigdatacorp_total_partners,
    CAST(bigdatacorp_total_household AS FLOAT) AS bigdatacorp_total_household,
    CAST(bigdatacorp_total_relationships AS FLOAT) AS bigdatacorp_total_relationships
  FROM 
    enriched_integration_report_data
  WHERE
    max_itr_timestamp = timestamp
    AND DATEDIFF(last_ca_timestamp, max_itr_timestamp) < 30
    AND bigdatacorp_integration_type = 'related_people'
),

internal_data AS (
  SELECT
    COALESCE(bd.id_proposal, pd.id_proposal) AS id_proposal,
    COALESCE(bd.id_proponent, pd.id_proponent) AS id_proponent,
    COALESCE(bd.cpf, pd.cpf) AS cpf,
    bigdatacorp_age,
    bigdatacorp_total_spouses,
    bigdatacorp_total_partners,
    bigdatacorp_total_household,
    bigdatacorp_total_relationships
  FROM 
    internal_basic_data AS bd
    FULL OUTER JOIN 
      internal_personal_data AS pd
        ON bd.id_proposal = pd.id_proposal 
        AND bd.id_proponent = pd.id_proponent 
        AND bd.cpf = pd.cpf
)

SELECT
  COALESCE(btest.id_proposal, idata.id_proposal) AS id_proposal,
  COALESCE(btest.id_proponent, idata.id_proponent) AS id_proponent,
  COALESCE(btest.cpf, idata.cpf) AS cpf,
  COALESCE(btest.bigdatacorp_age, idata.bigdatacorp_age) AS bigdatacorp_age,
  COALESCE(btest.bigdatacorp_total_spouses, idata.bigdatacorp_total_spouses) AS bigdatacorp_total_spouses,
  COALESCE(btest.bigdatacorp_total_partners, idata.bigdatacorp_total_partners) AS bigdatacorp_total_partners,
  COALESCE(btest.bigdatacorp_total_household, idata.bigdatacorp_total_household) AS bigdatacorp_total_household,
  COALESCE(btest.bigdatacorp_total_relationships, idata.bigdatacorp_total_relationships) AS bigdatacorp_total_relationships
FROM
  backtest btest
  FULL OUTER JOIN
    internal_data AS idata
      ON btest.id_proposal = idata.id_proposal
      AND btest.id_proponent = idata.id_proponent
      AND btest.cpf = idata.cpf