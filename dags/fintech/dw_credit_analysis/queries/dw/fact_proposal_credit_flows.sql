WITH credit_analysis AS (
  SELECT
    id_credit_analysis,
    id_proposal,
    guarantee_offered,
    guarantee_accepted,
    category,
    max_ca_category,
    is_bypass,
    ts_guarantee_accepted
  FROM
    datalake_credit_analysis.credit_analysis
),
credit_evaluation AS (
  SELECT
    cep.id_credit_evaluation,
    ce.id_user,
    ce.id_proposal,
    cep.proponent_type
  FROM
    datalake_docx_clean.credit_evaluation_proponent AS cep
  LEFT JOIN
    datalake_docx_clean.credit_evaluation AS ce ON cep.id_credit_evaluation = ce.id
  -- removing legacy data (latest record is 2021)
  WHERE cep.proponent_type IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY cep.id_credit_evaluation ORDER BY cep.ts_updated DESC) = 1
),
guarantees AS (
  SELECT
    flrf.sk_proposal,
    COUNT(
      DISTINCT CASE
        WHEN (
          CASE
            WHEN g.guarantee_type IN (
              'PRO_GUARANTOR',
              'STANDALONE',
              'DEPOSIT'
            )
            AND TO_DATE(
              CAST(
                NULLIF(flrf.sk_last_credit_evaluation_positive, -1) AS VARCHAR(8)
              ),
              'yyyyMMdd'
            ) IS NULL THEN TO_DATE(
              CAST(
                NULLIF(flrf.sk_last_credit_evaluation_negative, -1) AS VARCHAR(8)
              ),
              'yyyyMMdd'
            )
            ELSE TO_DATE(
              CAST(
                NULLIF(flrf.sk_last_credit_evaluation_positive, -1) AS VARCHAR(8)
              ),
              'yyyyMMdd'
            )
          END
        ) IS NULL
        AND g.guarantee_type IS NOT NULL THEN flrf.sk_proposal
        WHEN g.cancellation_reason = 'TenantStalled' then flrf.sk_proposal
        ELSE NULL
      END
    ) AS guarantee_not_accepted
  FROM
    dw_rent.fact_listing_rent_flows AS flrf
    LEFT JOIN
      datalake_rental_guarantee.guarantee AS g
        ON g.id_documentation_ebdb = flrf.sk_proposal
  WHERE
    g.guarantee_type != 'THIRD_PARTY_GUARANTEE'
  GROUP BY
    flrf.sk_proposal
),
credit_engine AS (
  SELECT DISTINCT
    ar.id_analysis_request,
    ar.id_proposal,
    ch.id_checklist
  FROM
    datalake_credit_analysis.credit_engine_analysis_request AS ar
  LEFT JOIN datalake_credit_analysis.credit_engine_checklist AS ch
    ON ch.id_analysis_request = ar.id_analysis_request
  WHERE ch.is_current_checklist = TRUE
),
direct_offer AS (
  SELECT
    f.sk_tenant_prospect AS sk_client,
    f.sk_house,
    d.first_touchpoint
  FROM
    dw_rent.fact_rent_flows f
  LEFT JOIN
    dw_rent.dim_rent_flow_type d
        ON f.sk_rent_flow_type = d.sk_rent_flow_type
  WHERE
    d.first_touchpoint = 'DIRECT'
  GROUP BY 1,2,3
),
early_demand AS (
  SELECT
    id_house AS sk_house,
    ts_early_demand_started
  FROM
    dw_public.dim_house_listing
  WHERE
    ts_early_demand_started IS NOT NULL
  QUALIFY
      ROW_NUMBER () OVER (PARTITION BY id_house ORDER BY sk_house_listing DESC) = 1
),
resend_request AS (
  SELECT
    id_proposal AS sk_proposal,
    count(*) AS resend_request
  FROM
    datalake_ebdb_clean.proposal_aud
  WHERE
    tenant_documentation_status = 'ReenvioDocumentos'
    AND mod_tenant_documentation_status = TRUE
  GROUP BY 1
),
proposal_proponents AS (
  SELECT
    id_proposal,
    COUNT(DISTINCT cpf) AS total_proposal_proponents,
    IF(COUNT(DISTINCT cpf) = 1, TRUE, FALSE) AS is_single_tenant
  FROM
    datalake_sorting_hat_clean.proponent
  GROUP BY
    id_proposal
),
rent_flows AS (
  SELECT
    flrf.sk_client,
    flrf.sk_house_listing,
    flrf.sk_contract,
    CAST(flrf.sk_house_listing / 1000 AS INTEGER) AS sk_house,
    flrf.sk_contract_created_date,
    TO_DATE(flrf.sk_contract_created_date::STRING, 'yyyyMMdd') AS dt_contract_created_date,
    flrf.sk_contract_signed_date,
    TO_DATE(flrf.sk_contract_signed_date::STRING, 'yyyyMMdd') AS dt_contract_signed_date,
    CAST(COALESCE(ca.id_credit_analysis, -1) AS INTEGER) AS sk_credit_analysis,
    CAST(COALESCE(ce.id_analysis_request, -1) AS INTEGER) AS sk_analysis_request,
    CAST(COALESCE(ce.id_checklist, -1) AS INTEGER) AS sk_checklist,
    flrf.sk_credit_analysis_approved_date,
    TO_DATE(flrf.sk_credit_analysis_approved_date::STRING, 'yyyyMMdd') AS dt_credit_analysis_approved_date,
    COALESCE(
      NULLIF(flrf.sk_last_credit_evaluation_positive, -1),
      CASE
        WHEN flrf.sk_last_credit_evaluation_positive < 0
        AND flrf.sk_last_credit_evaluation_negative > 0
        AND ca.category IS NOT NULL THEN flrf.sk_last_credit_evaluation_negative
      END,
      -1
    ) AS sk_credit_evaluation_approved_date,
    CAST(
      COALESCE(cap.id_first_credit_analysis, -1) AS INTEGER
    ) AS sk_first_credit_analysis,
    CAST(COALESCE(cap.id_first_variant, -1) AS INTEGER) AS sk_first_variant,
    CAST(
      COALESCE(cap.id_last_variant_not_null, -1) AS INTEGER
    ) AS sk_last_variant_not_null,
    COALESCE(ca.category, -1) AS sk_guarantee_category,
    flrf.sk_guarantee_paid_date,
    TO_DATE(flrf.sk_guarantee_paid_date::STRING, 'yyyyMMdd') AS dt_guarantee_paid_date,
    CAST(
      COALESCE(cap.id_last_credit_analysis, -1) AS INTEGER
    ) AS sk_last_credit_analysis,
    flrf.sk_last_credit_evaluation_init,
    flrf.sk_last_credit_evaluation_negative,
    flrf.sk_last_credit_evaluation_positive,
    flrf.sk_offer,
    flrf.sk_offer_approved_date,
    TO_DATE(flrf.sk_offer_approved_date::STRING, 'yyyyMMdd') AS dt_offer_approved_date,
    flrf.sk_offer_submitted_date,
    flrf.sk_proposal,
    flrf.sk_region,
    TO_DATE(flrf.sk_tenant_doc_complete_date::STRING, 'yyyyMMdd') AS dt_tenant_doc_complete_date,
    flrf.sk_tenant_doc_complete_date,
    flrf.sk_tenant_first_doc_sent_date,
    TO_DATE(ca.ts_guarantee_accepted) AS dt_guarantee_accepted_date,
    COALESCE(CAST(DATE_FORMAT(ca.ts_guarantee_accepted, "yyyyMMdd") AS BIGINT), -1) AS sk_guarantee_accepted_date,
    COALESCE(dp.id, -1) AS sk_drop_reason,
    flrf.funnel_step,
    ca.guarantee_offered AS guarantee_offered,
    ca.guarantee_accepted AS guarantee_accepted,
    IF(
      cap.id_first_credit_analysis = ca.id_credit_analysis,
      TRUE,
      FALSE
    ) AS is_first_credit_evaluation,
    IF(
      -- If the id_credit_analysis is null, it means that the proposal has dropped before ES
      (cap.id_last_credit_analysis = ca.id_credit_analysis OR ca.id_credit_analysis IS NULL),
      TRUE,
      FALSE
    ) AS is_last_credit_evaluation,
    dd.date AS dt_offer_submitted_date,
    hl.country_code,
    hl.rental_administrator,
    hl.version,
    ca.is_bypass,
    CASE
      WHEN ca.guarantee_accepted = 'CLEAR_NO' OR ca.guarantee_accepted = 'NOT_ACCEPTED' THEN FALSE
      WHEN ca.guarantee_accepted IS NULL THEN FALSE
      ELSE TRUE
    END AS is_guarantee_accepted, --fix rule: IF(g.guarantee_not_accepted = 1, TRUE, FALSE)
    pp.is_single_tenant,
    IF(ce.proponent_type = 'PERSON', FALSE, TRUE) AS is_renting_for_others,
    pp.total_proposal_proponents
  FROM
    dw_rent.fact_listing_rent_flows AS flrf
  LEFT JOIN
    datalake_credit_analysis.credit_analysis_proposals AS cap
      ON cap.id_proposal = flrf.sk_proposal
  LEFT JOIN
    credit_analysis AS ca
      ON cap.id_proposal = ca.id_proposal
  LEFT JOIN
    dw_public.dim_date AS dd
      ON flrf.sk_offer_submitted_date = dd.sk_date
  LEFT JOIN
    dw_rent.dim_house_listing AS hl
      ON hl.sk_house_listing = flrf.sk_house_listing
  LEFT JOIN
    guarantees AS g
      ON g.sk_proposal = flrf.sk_proposal
  LEFT JOIN
    dw_public.dim_drop_reason AS dp
      ON dp.desc_original_drop_reason = flrf.funnel_step_drop_reason
  LEFT JOIN
    credit_engine AS ce
      ON ce.id_proposal = flrf.sk_proposal
  LEFT JOIN
    proposal_proponents AS pp
      ON pp.id_proposal = flrf.sk_proposal
  LEFT JOIN
    credit_evaluation AS ce
      ON ce.id_user = flrf.sk_client
),
proposal_credit_flows AS (
  SELECT
    rf.sk_client,
    rf.sk_house_listing,
    rf.sk_house,
    rf.sk_contract,
    rf.sk_contract_created_date,
    rf.sk_contract_signed_date,
    rf.sk_credit_analysis,
    rf.sk_analysis_request,
    rf.sk_checklist,
    rf.sk_credit_analysis_approved_date,
    TO_DATE(rf.sk_credit_evaluation_approved_date::STRING, 'yyyyMMdd') AS dt_credit_evaluation_approved_date,
    rf.sk_credit_evaluation_approved_date,
    rf.sk_first_credit_analysis,
    rf.sk_first_variant,
    rf.sk_last_variant_not_null,
    rf.sk_guarantee_category,
    rf.sk_guarantee_paid_date,
    rf.sk_last_credit_analysis,
    rf.sk_last_credit_evaluation_init,
    TO_DATE(rf.sk_last_credit_evaluation_init::STRING, 'yyyyMMdd') AS dt_last_credit_evaluation_init,
    rf.sk_last_credit_evaluation_negative,
    rf.sk_last_credit_evaluation_positive,
    rf.sk_offer,
    rf.sk_offer_approved_date,
    rf.sk_offer_submitted_date,
    rf.sk_proposal,
    rf.sk_region,
    rf.sk_tenant_doc_complete_date,
    rf.sk_tenant_first_doc_sent_date,
    COALESCE(eca.sk_early_credit_analysis, -1) AS sk_early_credit_analysis,
    TO_DATE(rf.sk_tenant_first_doc_sent_date::STRING, 'yyyyMMdd') AS dt_tenant_first_doc_sent_date,
    rf.sk_guarantee_accepted_date,
    rf.sk_drop_reason,
    rf.funnel_step,
    rf.guarantee_offered,
    rf.guarantee_accepted,
    CASE
      WHEN rf.sk_offer_submitted_date > 0
      AND rf.sk_proposal < 0 THEN 'OS2OA'
      WHEN rf.sk_offer_approved_date > 0
      AND (
        rf.sk_last_credit_evaluation_init < 0
        OR rf.sk_last_credit_evaluation_init IS NULL
      ) THEN 'OA2ES'
      WHEN (
        rf.sk_last_credit_evaluation_init > 0
        AND rf.sk_credit_evaluation_approved_date < 0
      ) THEN 'ES2EP'
      WHEN (
        rf.sk_credit_evaluation_approved_date > 0
        AND rf.sk_tenant_first_doc_sent_date < 0
      ) THEN 'EP2DS'
      WHEN rf.sk_tenant_first_doc_sent_date > 0
      AND rf.sk_credit_analysis_approved_date < 0 THEN 'DS2CA'
      WHEN rf.sk_credit_analysis_approved_date > 0
      AND rf.sk_contract_signed_date < 0 THEN 'CA2CS'
      ELSE NULL
    END AS funnel_drop_step,
    CAST(
      COALESCE(
        REGEXP_REPLACE(CAST(eca.dt_early_credit_created AS VARCHAR(8)), '-', ''),
        -1
      ) AS INTEGER
    ) AS sk_early_credit_created,
    CAST(
      COALESCE(
        REGEXP_REPLACE(CAST(eca.dt_early_credit_expired AS VARCHAR(8)), '-', ''),
        -1
      ) AS INTEGER
    ) AS sk_early_credit_expired,
    rf.is_first_credit_evaluation,
    rf.is_last_credit_evaluation,
    rf.is_bypass,
    CASE
      WHEN eca.sk_early_credit_analysis IS NULL THEN FALSE
      ELSE TRUE
    END AS is_early_credit,
    rf.is_single_tenant,
    rf.is_renting_for_others,
    rf.total_proposal_proponents,
    rf.dt_tenant_doc_complete_date,
    rf.dt_credit_analysis_approved_date,
    rf.dt_offer_approved_date,
    rf.dt_guarantee_accepted_date,
    rf.dt_guarantee_paid_date,
    rf.dt_contract_created_date,
    rf.dt_contract_signed_date,
    CAST(eca.dt_early_credit_created AS DATE) AS dt_early_credit_created,
    CAST(eca.dt_early_credit_expired AS DATE) AS dt_early_credit_expired,
    rf.dt_offer_submitted_date,
    rf.country_code,
    rf.rental_administrator,
    rf.is_guarantee_accepted,
    ROW_NUMBER() OVER (
      PARTITION BY rf.sk_client,
      rf.sk_credit_analysis,
      rf.sk_house,
      rf.sk_offer
      ORDER BY
        rf.version DESC
    ) AS linsting_rank
  FROM
    rent_flows AS rf
  LEFT JOIN
    dw_credit.fact_offer_early_credit AS eca
      ON  rf.sk_offer = eca.sk_offer
),
house_listing AS (
  SELECT
    id_house,
    country_code,
    rental_administrator
  FROM
    dw_rent.dim_house_listing
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY sk_house_listing DESC) = 1
),
early_credit_full (
  SELECT
    eca.sk_client,
    -1 AS sk_house_listing,
    eca.sk_house,
    -1 AS sk_contract,
    -1 AS sk_contract_created_date,
    -1 AS sk_contract_signed_date,
    -1 AS sk_credit_analysis,
    eca.sk_early_credit_analysis,
    -1 AS sk_analysis_request,
    -1 AS sk_checklist,
    -1 AS sk_credit_analysis_approved_date,
    -1 AS sk_credit_evaluation_approved_date,
    -1 AS sk_first_credit_analysis,
    -1 AS sk_first_variant,
    -1 AS sk_last_variant_not_null,
    -1 AS sk_guarantee_category,
    -1 AS sk_guarantee_paid_date,
    -1 AS sk_guarantee_accepted_date,
    -1 AS sk_last_credit_analysis,
    -1 AS sk_last_credit_evaluation_init,
    -1 AS sk_last_credit_evaluation_negative,
    -1 AS sk_last_credit_evaluation_positive,
    -1 AS sk_offer,
    -1 AS sk_offer_approved_date,
    -1 AS sk_offer_submitted_date,
    -1 AS sk_proposal,
    -1 AS sk_region,
    -1 AS sk_tenant_doc_complete_date,
    -1 AS sk_tenant_first_doc_sent_date,
    -1 AS sk_drop_reason,
    REGEXP_REPLACE(CAST(eca.dt_early_credit_created AS VARCHAR(8)), '-', '') AS sk_early_credit_created,
    REGEXP_REPLACE(CAST(eca.dt_early_credit_expired AS VARCHAR(8)), '-', '') AS sk_early_credit_expired,
    'early_credit' AS funnel_step,
    'EC2OS' AS funnel_drop_step,
    CAST(NULL AS STRING) AS guarantee_offered,
    CAST(NULL AS STRING) AS guarantee_accepted,
    hl.country_code,
    hl.rental_administrator,
    CAST(NULL AS BOOLEAN) AS is_guarantee_accepted,
    CAST(NULL AS BOOLEAN) AS is_first_credit_evaluation,
    TRUE AS is_last_credit_evaluation,
    CAST(NULL AS BOOLEAN) AS is_bypass,
    TRUE AS is_early_credit,
    CAST(NULL AS BOOLEAN) AS is_single_tenant,
    CAST(NULL AS BOOLEAN) AS is_renting_for_others,
    CAST(NULL AS INTEGER) AS total_proposal_proponents,
    eca.dt_early_credit_created,
    eca.dt_early_credit_expired,
    CAST(NULL AS DATE) AS dt_last_credit_evaluation_init,
    CAST(NULL AS DATE) AS dt_tenant_first_doc_sent_date,
    CAST(NULL AS DATE) AS dt_offer_submitted_date,
    CAST(NULL AS DATE) AS dt_offer_approved_date,
    CAST(NULL AS DATE) AS dt_tenant_doc_complete_date,
    CAST(NULL AS DATE) AS dt_credit_evaluation_approved_date,
    CAST(NULL AS DATE) AS dt_credit_analysis_approved_date,
    CAST(NULL AS DATE) AS dt_guarantee_accepted_date,
    CAST(NULL AS DATE) AS dt_guarantee_paid_date,
    CAST(NULL AS DATE) AS dt_contract_created_date,
    CAST(NULL AS DATE) AS dt_contract_signed_date,
    CAST(NULL AS DATE) AS dt_reference,
    NOW() AS ts_load
  FROM
    dw_credit.fact_early_credit AS eca
  LEFT JOIN
    house_listing AS hl
      ON  hl.id_house = eca.sk_house
  LEFT JOIN
    proposal_credit_flows AS pcf
      ON  pcf.sk_early_credit_analysis = eca.sk_early_credit_analysis
  WHERE pcf.sk_early_credit_analysis IS NULL
),
final_flow AS (
SELECT
  sk_client,
  sk_house_listing,
  sk_house,
  sk_contract,
  sk_contract_created_date,
  sk_contract_signed_date,
  sk_credit_analysis,
  sk_early_credit_analysis,
  sk_analysis_request,
  sk_checklist,
  sk_credit_analysis_approved_date,
  sk_credit_evaluation_approved_date,
  sk_first_credit_analysis,
  sk_first_variant,
  sk_last_variant_not_null,
  sk_guarantee_category,
  sk_guarantee_paid_date,
  sk_guarantee_accepted_date,
  sk_last_credit_analysis,
  sk_last_credit_evaluation_init,
  sk_last_credit_evaluation_negative,
  sk_last_credit_evaluation_positive,
  sk_offer,
  sk_offer_approved_date,
  sk_offer_submitted_date,
  sk_proposal,
  sk_region,
  sk_tenant_doc_complete_date,
  sk_tenant_first_doc_sent_date,
  sk_drop_reason,
  sk_early_credit_created,
  sk_early_credit_expired,
  funnel_step,
  -- This rule is necessary to guarantee that the drop step is correct when the guarantee is not accepted
  CASE
	  WHEN funnel_drop_step = 'EP2DS' AND guarantee_accepted = 'NOT_ACCEPTED' THEN 'ES2EP'
	  ELSE funnel_drop_step
  END AS funnel_drop_step,
  guarantee_offered,
  guarantee_accepted,
  country_code,
  rental_administrator,
  is_guarantee_accepted,
  is_first_credit_evaluation,
  is_last_credit_evaluation,
  is_bypass,
  is_early_credit,
  is_single_tenant,
  is_renting_for_others,
  total_proposal_proponents,
  dt_early_credit_created,
  dt_early_credit_expired,
  dt_last_credit_evaluation_init,
  dt_tenant_first_doc_sent_date,
  dt_offer_submitted_date,
  dt_offer_approved_date,
  dt_tenant_doc_complete_date,
  dt_credit_evaluation_approved_date,
  dt_credit_analysis_approved_date,
  dt_guarantee_accepted_date,
  dt_guarantee_paid_date,
  dt_contract_created_date,
  dt_contract_signed_date,
  CAST(NULL AS DATE) AS dt_reference,
  NOW() AS ts_load
FROM
  proposal_credit_flows
WHERE
  sk_offer_submitted_date > 0
  AND linsting_rank = 1
UNION
SELECT
  *
FROM
  early_credit_full
),
add_dt_reference AS (
SELECT
  sk_client,
  sk_house_listing,
  sk_house,
  sk_contract,
  sk_contract_created_date,
  sk_contract_signed_date,
  sk_credit_analysis,
  sk_early_credit_analysis,
  sk_analysis_request,
  sk_checklist,
  sk_credit_analysis_approved_date,
  sk_credit_evaluation_approved_date,
  sk_first_credit_analysis,
  sk_first_variant,
  sk_last_variant_not_null,
  sk_guarantee_category,
  sk_guarantee_paid_date,
  sk_guarantee_accepted_date,
  sk_last_credit_analysis,
  sk_last_credit_evaluation_init,
  sk_last_credit_evaluation_negative,
  sk_last_credit_evaluation_positive,
  sk_offer,
  sk_offer_approved_date,
  sk_offer_submitted_date,
  sk_proposal,
  sk_region,
  sk_tenant_doc_complete_date,
  sk_tenant_first_doc_sent_date,
  sk_drop_reason,
  sk_early_credit_created,
  sk_early_credit_expired,
  funnel_step,
  funnel_drop_step,
  CASE
    WHEN funnel_drop_step = 'EC2OS' THEN 'A. EC2OS'
    WHEN funnel_drop_step = 'OS2OA' THEN 'B. OS2OA'
    WHEN funnel_drop_step = 'OA2ES' THEN 'C. OA2ES'
    WHEN funnel_drop_step = 'ES2EP' THEN 'D. ES2EP'
    WHEN funnel_drop_step = 'EP2DS' THEN 'E. EP2DS'
    WHEN funnel_drop_step = 'DS2CA' THEN 'F. DS2CA'
    WHEN funnel_drop_step = 'CA2CS' THEN 'G. CA2CS'
    ELSE NULL
  END AS funnel_drop_step_ordered,
  guarantee_offered,
  guarantee_accepted,
  country_code,
  rental_administrator,
  is_guarantee_accepted,
  is_first_credit_evaluation,
  is_last_credit_evaluation,
  is_bypass,
  is_early_credit,
  is_single_tenant,
  is_renting_for_others,
  total_proposal_proponents,
  dt_early_credit_created,
  dt_early_credit_expired,
  dt_last_credit_evaluation_init,
  dt_tenant_first_doc_sent_date,
  dt_offer_submitted_date,
  dt_offer_approved_date,
  dt_tenant_doc_complete_date,
  dt_credit_evaluation_approved_date,
  dt_credit_analysis_approved_date,
  dt_guarantee_accepted_date,
  dt_guarantee_paid_date,
  dt_contract_created_date,
  dt_contract_signed_date,
  COALESCE(dt_offer_submitted_date, dt_early_credit_created) AS dt_reference,
  ts_load
FROM
  final_flow
),
client_max_funnel_drop_step AS (
SELECT
  sk_client AS sk_client_max_funnel,
  DATE_TRUNC('month', dt_reference) AS dt_reference_user_max_funnel,
  funnel_drop_step_ordered AS client_max_funnel_drop_step
FROM
  add_dt_reference
WHERE
  country_code = 'BR' AND
	rental_administrator = 'QUINTOANDAR' AND
  is_last_credit_evaluation = TRUE
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY CASE WHEN sk_client IS NULL THEN 1 ELSE sk_client END, DATE_TRUNC('month',dt_reference) ORDER BY IF(funnel_drop_step_ordered IS NULL, "Z", funnel_drop_step_ordered) DESC) = 1
)
SELECT
  adr.sk_client,
  adr.sk_house_listing,
  adr.sk_house,
  sk_contract,
  sk_contract_created_date,
  sk_contract_signed_date,
  sk_credit_analysis,
  sk_early_credit_analysis,
  sk_analysis_request,
  sk_checklist,
  sk_credit_analysis_approved_date,
  sk_credit_evaluation_approved_date,
  sk_first_credit_analysis,
  sk_first_variant,
  sk_last_variant_not_null,
  sk_guarantee_category,
  sk_guarantee_paid_date,
  sk_guarantee_accepted_date,
  sk_last_credit_analysis,
  sk_last_credit_evaluation_init,
  sk_last_credit_evaluation_negative,
  sk_last_credit_evaluation_positive,
  sk_offer,
  sk_offer_approved_date,
  sk_offer_submitted_date,
  adr.sk_proposal,
  sk_region,
  sk_tenant_doc_complete_date,
  sk_tenant_first_doc_sent_date,
  sk_drop_reason,
  sk_early_credit_created,
  sk_early_credit_expired,
  funnel_step,
  funnel_drop_step,
  funnel_drop_step_ordered,
  umf.client_max_funnel_drop_step,
  guarantee_offered,
  guarantee_accepted,
  country_code,
  rental_administrator,
  CASE
    WHEN sk_early_credit_analysis <> -1
    THEN 1 ELSE 0
  END AS ec_flag,
  CASE
    WHEN sk_offer <> -1
    THEN 1 ELSE 0
  END AS os_flag,
  CASE
    WHEN funnel_drop_step_ordered IN ('A. EC2OS',  'B. OS2OA')
    THEN 0 ELSE 1
  END AS oa_flag,
  CASE
    WHEN funnel_drop_step_ordered IN ('A. EC2OS',  'B. OS2OA',  'C. OA2ES')
    THEN 0 ELSE 1
  END AS es_flag,
  CASE
    WHEN funnel_drop_step_ordered IN ('A. EC2OS',  'B. OS2OA',  'C. OA2ES',  'D. ES2EP')
    THEN 0 ELSE 1
  END AS ep_flag,
  CASE
    WHEN funnel_drop_step_ordered IN ('A. EC2OS',  'B. OS2OA',  'C. OA2ES',  'D. ES2EP',  'E. EP2DS')
    THEN 0 ELSE 1
  END AS ds_flag,
  CASE
    WHEN funnel_drop_step_ordered IN ('A. EC2OS',  'B. OS2OA',  'C. OA2ES',  'D. ES2EP',  'E. EP2DS',  'F. DS2CA')
    THEN 0 ELSE 1
  END AS ca_flag,
  CASE
    WHEN funnel_drop_step_ordered IN ('A. EC2OS',  'B. OS2OA',  'C. OA2ES',  'D. ES2EP',  'E. EP2DS',  'F. DS2CA',  'G. CA2CS')
    THEN 0 ELSE 1
  END AS cs_flag,
  is_guarantee_accepted,
  is_first_credit_evaluation,
  is_last_credit_evaluation,
  is_bypass,
  is_early_credit,
  CASE
    WHEN
    ROW_NUMBER() OVER (
      PARTITION BY
        adr.sk_client,
        date_trunc('MONTH',adr.dt_reference),
        umf.client_max_funnel_drop_step
      ORDER BY
        CASE WHEN rental_administrator <> 'QUINTOANDAR' THEN NULL ELSE rental_administrator END DESC,
        CASE WHEN country_code <> 'BR' THEN NULL ELSE country_code END DESC,
        CASE WHEN is_last_credit_evaluation = FALSE THEN NULL ELSE is_last_credit_evaluation END DESC,
        CASE WHEN adr.funnel_drop_step_ordered IS NULL THEN 'Z. FULL_FUNNEL' ELSE adr.funnel_drop_step_ordered END DESC,
        sk_credit_analysis DESC
      ) = 1 THEN TRUE
    ELSE FALSE
  END as is_user_version,
  IF(df.first_touchpoint IS NULL, FALSE, TRUE) AS is_direct_offer,
  IF(ed.ts_early_demand_started IS NULL, FALSE, TRUE) AS is_early_demand,
  IF(dt_tenant_first_doc_sent_date IS NOT NULL AND rr.resend_request IS NOT NULL, TRUE, FALSE) AS is_resend_request,
  is_single_tenant,
  is_renting_for_others,
  total_proposal_proponents,
  dt_early_credit_created,
  dt_early_credit_expired,
  dt_last_credit_evaluation_init,
  dt_tenant_first_doc_sent_date,
  dt_offer_submitted_date,
  dt_offer_approved_date,
  dt_tenant_doc_complete_date,
  dt_credit_evaluation_approved_date,
  dt_credit_analysis_approved_date,
  dt_guarantee_accepted_date,
  dt_guarantee_paid_date,
  dt_contract_created_date,
  dt_contract_signed_date,
  dt_reference,
  ts_load
FROM
  add_dt_reference adr
LEFT JOIN
  client_max_funnel_drop_step umf
  ON adr.sk_client = umf.sk_client_max_funnel
  AND DATE_TRUNC('month', adr.dt_reference) = umf.dt_reference_user_max_funnel
LEFT JOIN
  direct_offer df
  ON  df.sk_client = adr.sk_client
  AND df.sk_house = adr.sk_house
LEFT JOIN
  early_demand ed
  ON ed.sk_house = adr.sk_house
LEFT JOIN
  resend_request rr
  ON rr.sk_proposal = adr.sk_proposal
