WITH tenant_contract AS (
  SELECT
    cp.id_user_contract_person AS sk_user_fcp,
    cp.personal_document AS contract_cpf,
    cp.id_contract AS id_contract,
    dc.ts_created AS contract_ts_created,
    dc.dt_started AS contract_dt_start,
    dc.dt_termination AS contract_dt_annulment,
    flrf.sk_proposal AS contract_id_proposal,
    flrf.sk_client AS sk_client_flrf
  FROM
    datalake_ebdb_contract.contract_person AS cp
  INNER JOIN
    datalake_ebdb_contract.contract AS dc
      ON dc.id = cp.id_contract
      AND dc.status <> 'Cancelado'
  INNER JOIN
    dw_rent.fact_listing_rent_flows AS flrf
      ON dc.id = flrf.sk_contract
  WHERE
    cp.contract_role IN ('tenant')
    AND cp.id_user_contract_person IS NOT NULL
),
proposal_tenant AS (
  SELECT
    pl.id AS id_proposal,
    pl.ts_created AS proposal_ts_created,
    pt.cpf AS proposal_cpf
  FROM
    datalake_sorting_hat_clean.proposal AS pl
  INNER JOIN
    datalake_sorting_hat_clean.proponent AS pt
      ON pl.id = pt.id_proposal
  WHERE
    pt.cpf IS NOT NULL
),
proposal_last_contract AS (
  SELECT
    plt.id_proposal,
    plt.proposal_ts_created,
    plt.proposal_cpf,
    tc.sk_user_fcp,
    tc.contract_cpf,
    tc.id_contract,
    tc.contract_ts_created,
    tc.contract_dt_start,
    tc.contract_dt_annulment,
    tc.contract_id_proposal,
    tc.sk_client_flrf
  FROM
    proposal_tenant AS plt
  INNER JOIN
    tenant_contract AS tc
      ON tc.contract_cpf = plt.proposal_cpf
  WHERE
    plt.proposal_ts_created > tc.contract_dt_start
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY plt.id_proposal, plt.proposal_cpf ORDER BY tc.contract_dt_start DESC) = 1
),
proposal_retenant AS (
  SELECT
    pt.id_proposal,
    pt.proposal_cpf,
    pt.proposal_ts_created,
    plc.id_contract AS last_contract,
    tc.sk_user_fcp,
    tc.contract_cpf,
    tc.contract_ts_created,
    tc.contract_dt_start,
    tc.contract_dt_annulment,
    tc.contract_id_proposal,
    tc.sk_client_flrf,
    CASE
      WHEN pt.proposal_cpf = tc.contract_cpf THEN 1
      ELSE 0
    END AS equal_cpf_sk_personal_document,
    CASE
      WHEN pt.proposal_cpf = tc.contract_cpf
      AND tc.sk_user_fcp = tc.sk_client_flrf THEN 1
      ELSE 0
    END AS equal_main_contract_proposal
  FROM
    proposal_tenant AS pt
    LEFT JOIN
      proposal_last_contract AS plc
        ON plc.id_proposal = pt.id_proposal
        AND pt.proposal_cpf = plc.proposal_cpf
    FULL OUTER JOIN
      tenant_contract AS tc
        ON plc.id_contract = tc.id_contract
        AND plc.proposal_cpf = tc.contract_cpf
    WHERE
      pt.id_proposal IS NOT NULL
),
proposal_retenant_count_p AS (
  SELECT
    id_proposal,
    COUNT(proposal_cpf) AS count_cpf_proposal,
    COUNT(DISTINCT proposal_cpf) AS distinct_cpf_proposal
  FROM
    proposal_retenant
  GROUP BY
    id_proposal
),
proposal_retenant_count_c AS (
  SELECT
    id_proposal,
    proposal_ts_created,
    last_contract,
    contract_dt_annulment,
    MAX(contract_ts_created) AS contract_ts_created,
    COUNT(contract_cpf) AS count_cpf_contract,
    COUNT(DISTINCT contract_cpf) AS distinct_cpf_contract,
    SUM(equal_cpf_sk_personal_document) AS equal_cpf_contract,
    SUM(equal_main_contract_proposal) AS is_main_proponent_contract_proposal
  FROM
    proposal_retenant
  WHERE
    last_contract IS NOT NULL
  GROUP BY
    id_proposal,
    contract_dt_annulment,
    proposal_ts_created,
    last_contract
  ORDER BY
    id_proposal
),
proposal_retenant_count AS (
  SELECT
    prcp.id_proposal,
    prcp.count_cpf_proposal,
    prcp.distinct_cpf_proposal,
    prcc.proposal_ts_created,
    prcc.last_contract,
    prcc.contract_dt_annulment,
    prcc.contract_ts_created,
    prcc.count_cpf_contract,
    prcc.distinct_cpf_contract,
    prcc.equal_cpf_contract,
    prcc.is_main_proponent_contract_proposal
  FROM
    proposal_retenant_count_p AS prcp
  LEFT JOIN
    proposal_retenant_count_c AS prcc
      ON prcp.id_proposal = prcc.id_proposal
),
proposal_contract_label AS (
  SELECT
    prc.id_proposal,
    ca.id_credit_analysis AS sk_credit_analysis,
    prc.last_contract AS last_active_contract,
    CASE
      WHEN prc.contract_dt_annulment < prc.proposal_ts_created THEN DATEDIFF(
        MONTH,
        DATE_TRUNC('month', prc.contract_dt_annulment),
        DATE_TRUNC('month', DATE(prc.proposal_ts_created))
      )
      ELSE NULL
    END AS contract_age,
    (
      CASE
        WHEN prc.count_cpf_contract <> 0 THEN 'retenant'
        ELSE 'newcustomer'
      END
    ) AS any_proponent,
    (
      CASE
        WHEN prc.is_main_proponent_contract_proposal <> 0
        AND prc.count_cpf_contract <> 0 THEN 'retenant'
        ELSE 'newcustomer'
      END
    ) AS main_proponent,
    (
      CASE
        WHEN prc.distinct_cpf_proposal > prc.distinct_cpf_contract
        AND prc.is_main_proponent_contract_proposal <> 0
        AND prc.count_cpf_contract <> 0 THEN 'retenant'
        ELSE 'newcustomer'
      END
    ) AS main_proponent_with_more_proponents_in_proposal,
    (
      CASE
        WHEN prc.distinct_cpf_proposal = prc.distinct_cpf_contract
        AND prc.is_main_proponent_contract_proposal <> 0
        AND prc.equal_cpf_contract <> prc.distinct_cpf_contract
        AND prc.count_cpf_contract <> 0 THEN 'retenant'
        ELSE 'newcustomer'
      END
    ) AS main_proponent_with_different_proponents_in_proposal,
    (
      CASE
        WHEN prc.distinct_cpf_proposal < prc.distinct_cpf_contract
        AND prc.is_main_proponent_contract_proposal <> 0
        AND prc.count_cpf_contract <> 0 THEN 'retenant'
        ELSE 'newcustomer'
      END
    ) AS main_proponent_with_fewer_proponents_in_proposal,
    (
      CASE
        WHEN prc.distinct_cpf_proposal = prc.distinct_cpf_contract
        AND prc.equal_cpf_contract = prc.distinct_cpf_contract
        AND prc.count_cpf_contract <> 0 THEN 'retenant'
        ELSE 'newcustomer'
      END
    ) AS equal_proponents_in_proposal,
    CASE
      WHEN DATE(p.ts_created) > '2023-12-05' THEN 'new_retenant_policy'
      ELSE 'old_retenant_policy'
    END AS retenant_policy,
    prc.contract_dt_annulment AS dt_contract_annulment,
    COALESCE(prc.proposal_ts_created, p.ts_created) AS ts_proposal_created,
    prc.contract_ts_created AS ts_last_contract_created
  FROM
    proposal_retenant_count AS prc
  LEFT JOIN
    datalake_sorting_hat_clean.proposal AS p
      ON p.id = prc.id_proposal
  LEFT JOIN datalake_sorting_hat_clean.credit_analysis AS ca
    ON ca.id_proposal = prc.id_proposal
),
get_active_contract_per_credit_analysis AS (
  SELECT
    sk_credit_analysis,
    COUNT(DISTINCT last_active_contract) AS number_of_contracts
  FROM
    proposal_contract_label
  GROUP BY sk_credit_analysis
)
SELECT
  pcl.sk_credit_analysis,
  pcl.last_active_contract,
  cpca.number_of_contracts,
  pcl.contract_age,
  CASE 
    WHEN( pcl.main_proponent_with_more_proponents_in_proposal = "retenant" 
    OR    pcl.main_proponent_with_different_proponents_in_proposal = "retenant" 
    OR    pcl.main_proponent_with_fewer_proponents_in_proposal = "retenant" )
      THEN  "new_group_same_main_proponent"
    WHEN  pcl.main_proponent = "retenant" 
    AND   pcl.equal_proponents_in_proposal = "retenant"
      THEN "same_group_same_main_proponent"
    WHEN  pcl.main_proponent = "retenant"
      THEN "main_proponent_only"
    WHEN  pcl.any_proponent = "retenant"
      THEN "group_member_only"
    ELSE  "newcustomer"
  END AS retenant_type,
  pcl.any_proponent,
  pcl.main_proponent,
  pcl.main_proponent_with_more_proponents_in_proposal,
  pcl.main_proponent_with_different_proponents_in_proposal,
  pcl.main_proponent_with_fewer_proponents_in_proposal,
  pcl.equal_proponents_in_proposal,
  pcl.retenant_policy,
  CASE 
    WHEN pcl.main_proponent = "retenant" THEN TRUE
    WHEN pcl.any_proponent  = "retenant" THEN TRUE
    ELSE FALSE
  END AS is_retenant,
  pcl.dt_contract_annulment,
  pcl.ts_proposal_created,
  pcl.ts_last_contract_created,
  NOW() AS ts_load
FROM
  proposal_contract_label AS pcl
LEFT JOIN
  get_active_contract_per_credit_analysis AS cpca
    ON cpca.sk_credit_analysis = pcl.sk_credit_analysis
WHERE pcl.sk_credit_analysis IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY pcl.sk_credit_analysis ORDER BY pcl.ts_last_contract_created DESC) = 1
