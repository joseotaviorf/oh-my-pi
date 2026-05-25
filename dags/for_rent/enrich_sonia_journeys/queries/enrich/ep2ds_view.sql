WITH all_flows_base AS (
   SELECT
    CAST(CONCAT(of_ebdb.id, '02') AS BIGINT) AS id_offer,
    of_ebdb.id_client AS id_user,
    of_ebdb.id_house,
    CASE
      WHEN cav_sh.category IS NULL
        AND (
          cav_sh.bypass IS NULL
          OR TRY_CAST(cav_sh.bypass AS BOOLEAN) = FALSE
        )
        AND cav_sh.automatic_decision_reason <> 'INSUFFICIENT_INCOME'
        AND cav_sh.result = 'REJECTED'
        THEN TRUE
      ELSE FALSE
    END AS is_clear_no,
    CASE
      WHEN of_ebdb.ts_expired > NOW()
        AND of_ebdb.rejection_reason IS NULL
        AND of_ebdb.status != 'Rejeitada' THEN TRUE
      ELSE FALSE
    END AS is_offer_active,
    pr_ebdb.id AS id_proposal,
    pr_ebdb.status AS proposal_status,
    pr_ebdb.tenant_documentation_status,
    ct_ebdb.id AS id_contract,
    COALESCE(ct_ebdb.ts_minuta_approved, ct_ebdb.ts_updated) + INTERVAL '7 days' AS expiration_date,
    pr_ebdb.rejection_reason AS proposal_rejection_reason,
    pr_ebdb.ts_created AS ts_proposal_created,
    pr_ebdb.ts_expired AS ts_proposal_expired,
    cav_sh.result AS credit_analysis_result,
    cav_sh.automatic_decision_reason,
    ct_ebdb.status AS contract_status,
    cav_sh.ts_created AS ts_evaluation_positive,
    COALESCE(TRY_CAST(cav_sh.bypass AS BOOLEAN), FALSE) AS is_bypass
  FROM datalake_ebdb_clean.offer AS of_ebdb
  LEFT JOIN datalake_ebdb_clean.proposal AS pr_ebdb
    ON of_ebdb.id = pr_ebdb.id_offer
  LEFT JOIN datalake_ebdb_clean.contract AS ct_ebdb
    ON pr_ebdb.id = ct_ebdb.id_proposal
  LEFT JOIN datalake_sorting_hat_clean.credit_analysis AS cav_sh
    ON pr_ebdb.id = cav_sh.id_proposal
  WHERE cav_sh.ts_created >= TIMESTAMP '2026-05-26 00:00:00'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pr_ebdb.id ORDER BY cav_sh.ts_created DESC) = 1
),
all_flows_status AS (
  SELECT
    afb.*,
    CASE
      WHEN afb.id_proposal IS NULL THEN NULL
      WHEN afb.proposal_rejection_reason = 'CreditEvaluationRejected'
        AND afb.credit_analysis_result = 'APPROVED'
        AND afb.ts_proposal_created + INTERVAL '5 days' < NOW() THEN FALSE
      WHEN afb.proposal_rejection_reason = 'CreditEvaluationRejected'
        AND afb.credit_analysis_result = 'APPROVED'
        AND afb.ts_proposal_created + INTERVAL '5 days' > NOW() THEN TRUE
      WHEN afb.proposal_rejection_reason = 'CreditEvaluationRejected'
        AND afb.credit_analysis_result = 'REJECTED'
        AND afb.is_clear_no = FALSE
        AND afb.ts_proposal_created + INTERVAL '5 days' > NOW() THEN TRUE
      WHEN afb.proposal_rejection_reason IS NULL
        AND (afb.ts_proposal_expired IS NULL OR afb.ts_proposal_expired > NOW()) THEN TRUE
      ELSE FALSE
    END AS is_proposal_active,
    CASE
      WHEN afb.id_contract IS NULL THEN NULL
      WHEN afb.contract_status IN ('PreAssinaturas', 'Minuta')
        AND afb.expiration_date > NOW() THEN TRUE
      ELSE FALSE
    END AS is_contract_waiting_sign
  FROM all_flows_base AS afb
),
all_flows AS (
  SELECT
    afs.id_offer,
    afs.id_user,
    afs.id_house,
    afs.is_clear_no,
    afs.is_offer_active,
    afs.id_proposal,
    afs.proposal_status,
    afs.tenant_documentation_status,
    afs.is_proposal_active,
    afs.id_contract,
    afs.expiration_date,
    afs.is_contract_waiting_sign,
    COALESCE(afs.is_contract_waiting_sign, afs.is_proposal_active, afs.is_offer_active) AS is_active_flow,
    afs.ts_evaluation_positive,
    afs.is_bypass
  FROM all_flows_status AS afs
),
documentation_completed_events AS (
  SELECT
    TRY_CAST(cdp_tx.event_properties:proposal_id AS INT) AS id_proposal,
    MAX(cdp_tx.ts_event) AS ts_documentation_completed
  FROM datalake_cdp_clean.transactional AS cdp_tx
  WHERE cdp_tx.event_name = 'tenant_documentation_completed_event'
    AND TRY_CAST(cdp_tx.event_properties:proposal_id AS INT) IS NOT NULL
  GROUP BY TRY_CAST(cdp_tx.event_properties:proposal_id AS INT)
),
getting_ep_cases AS (
  SELECT
    af.*,
    hs.address,
    hs.number,
    hs.complement,
    hs.neighborhood,
    hs.city,
    DECODE(pr_sh.proposal_source, 'DEFAULT', FALSE, TRUE) AS is_credit_passport,
    us_ebdb.uuid_person AS uuid_user,
    us_ebdb.email AS user_email,
    REPLACE(us_ebdb.main_phone, '+', '') AS user_phone,
    us_ebdb.name AS user_name,
    (dce.id_proposal IS NOT NULL) AS documentation_sent,
    dce.ts_documentation_completed AS ts_documentation_sent,
    EXISTS (
      SELECT 1
      FROM datalake_copilot_service_clean.session s
      INNER JOIN datalake_copilot_service_clean.message m
        ON m.id_session = s.id
      WHERE TRY_CAST(s.id_user AS BIGINT) = af.id_user
        AND s.ts_created >= af.ts_evaluation_positive
        AND m.channel = 'WHATSAPP_SONIA_CHAT'
    ) AS has_answered
  FROM all_flows AS af
  INNER JOIN datalake_sorting_hat_clean.proposal AS pr_sh
    ON af.id_proposal = pr_sh.id
  INNER JOIN datalake_ebdb_clean.user AS us_ebdb
    ON af.id_user = us_ebdb.id
  LEFT JOIN documentation_completed_events AS dce
    ON af.id_proposal = dce.id_proposal
    AND dce.ts_documentation_completed >= af.ts_evaluation_positive
  LEFT JOIN datalake_ebdb_clean.house AS hs
    ON af.id_house = hs.id
  WHERE af.proposal_status = 'EmAnalise'
    AND af.tenant_documentation_status IN ('AnaliseCredito', 'RecusadoCredito')
)
SELECT
  CONCAT(CAST(gec.id_proposal AS STRING), '_', CAST(gec.uuid_user AS STRING)) AS pk_proposal_user,
  gec.id_user,
  gec.uuid_user,
  gec.id_proposal,
  CONCAT(
    'https://www.quintoandar.com.br/documentacao/',
    CAST(gec.id_proposal AS STRING),
    '?source_platform=sonia&utm_source=sonia'
  ) AS documentation_url,
  gec.id_house,
  MAX(gec.is_active_flow) AS is_active_flow,
  MAX(gec.documentation_sent) AS documentation_sent,
  MAX(gec.has_answered) AS has_answered,
  gec.user_email,
  gec.user_phone,
  MAX(split_part(gec.user_name, ' ', 1)) AS user_first_name,
  MAX(CONCAT_WS(', ', gec.address, CAST(gec.number AS STRING))) AS address_text,
  ABS(CRC32(ENCODE(CAST(gec.uuid_user AS STRING), 'utf-8'))) % 100 AS binning_value,
  MAX(gec.ts_evaluation_positive) AS ts_evaluation_positive,
  MAX(gec.ts_documentation_sent) AS ts_documentation_sent
FROM getting_ep_cases AS gec
WHERE gec.is_credit_passport IS FALSE
  AND gec.is_bypass IS FALSE
GROUP BY
  CONCAT(CAST(gec.id_proposal AS STRING), '_', CAST(gec.uuid_user AS STRING)),
  gec.id_user,
  gec.uuid_user,
  gec.id_proposal,
  gec.id_house,
  gec.user_email,
  gec.user_phone;
