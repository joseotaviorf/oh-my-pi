-- eval_model_seamless_offboarding: ground-truth view for seamless offboarding model evaluation.
-- Grain: one row per contract (id_contract), with ticket classification and model prediction.
-- Spine: terminator (all SPOC-eligible contracts with model prediction since 2026-04-01).
-- Offboarding window: ts_termination_request → ts_termination_finished + 10 days (from fact_terminations).
-- Mediação: from obt_offboarding.has_mediation_ticket.
-- Agendamento Vistoria: Zendesk only counts from the 2nd occurrence onward (rn > 1);
-- Salesforce record type already represents Reagendamento de Vistoria.
-- Back Escalado: Zendesk (pre_tickets) for legacy; Salesforce via dw_bpo_performance.cases_perspective
--   for migrated tickets. TODO: add cutoff date to pre_tickets 'back escaladado' branch once
--   migration date is confirmed, to avoid double-counting.
-- Note: SPOC_ELIGIBILITY_QUERY join not included — SPOC flag from fact_terminations only.
--   TODO: add join to spoc eligibility table and replace is_spoc_eligible_terminator with
--         COALESCE(GREATEST(is_spoc_eligible_terminator, spoc.spoc_eligible), FALSE).

WITH model_infos AS (
  SELECT
    get_json_object(inputs, '$.request_id')   AS id_request,
    get_json_object(inputs, '$.contract_id')  AS id_contract_request,
    get_json_object(outputs, '$.prediction')  AS prediction,
    get_json_object(outputs, '$.probability') AS probability,
    ts_log
  FROM datalake_emlio_clean.emlio_logs
  WHERE id_service = 'users-and-journeys-ml-service'
    AND CAST(ts_log AS DATE) >= DATE('2026-04-01')
    AND CAST(ts_log AS DATE) >= ADD_MONTHS(CURRENT_DATE(), -6)
),

-- Spine: all SPOC-eligible terminations with model predictions since 2026-04-01.
terminator AS (
  SELECT
    t.id AS sk_termination,
    t.id_contract,
    t.ts_created,
    t.spoc_wave,
    t.is_spoc,
    t.team,
    m.id_request,
    m.id_contract_request,
    m.prediction,
    m.probability,
    m.ts_log
  FROM datalake_terminator_clean.termination t
  LEFT JOIN model_infos m
    ON CAST(m.id_request AS INTEGER) = t.id
  WHERE CAST(t.ts_created AS DATE) >= DATE('2026-04-01')
    AND CAST(t.ts_created AS DATE) >= ADD_MONTHS(CURRENT_DATE(), -6)
    AND t.is_spoc_eligible = 'true'
),

-- Offboarding window and mediação flag, joined from DW tables.
-- LEFT JOIN: keeps all terminator rows even if fact_terminations has no match.
terminator_enriched AS (
  SELECT
    t.sk_termination,
    t.id_contract,
    t.ts_created,
    t.spoc_wave,
    t.is_spoc,
    t.team,
    t.id_request,
    t.id_contract_request,
    t.prediction,
    t.probability,
    t.ts_log,
    dc.sk_contract,
    fc.sk_tenant,
    fc.sk_owner,
    COALESCE(ft.ts_termination_request, t.ts_created)                      AS ts_offboarding_start,
    COALESCE(DATEADD(DAY, 10, ft.ts_termination_finished), CURRENT_DATE()) AS ts_last_date_for_target,
    CAST(ft.is_spoc_eligible AS BOOLEAN)                                    AS is_spoc_eligible_terminator,
    CASE WHEN obt.sk_contract IS NOT NULL THEN 1 ELSE 0 END                 AS is_mediacao
  FROM terminator t
  LEFT JOIN dw_rent.dim_contract dc
    ON dc.id_contract = t.id_contract
  LEFT JOIN dw_offboarding.fact_terminations ft
    ON ft.sk_contract = dc.sk_contract
    AND ft.sk_termination = t.sk_termination
  LEFT JOIN dw_rent.fact_contracts fc
    ON fc.sk_contract = dc.sk_contract
  LEFT JOIN (
    SELECT sk_contract, sk_termination, has_mediation_ticket
    FROM dw_offboarding.obt_offboarding
    WHERE has_mediation_ticket IS TRUE
  ) obt
    ON obt.sk_contract = dc.sk_contract
    AND obt.sk_termination = t.sk_termination
),

-- Customer Support (Zendesk) tickets classified as offboarding-related contact.
-- Mediação removed from here — sourced from obt_offboarding in terminator_enriched.
-- Back Escalado kept here for legacy/Zendesk period; Salesforce migration in salesforce_back_escalado.
pre_tickets AS (
  SELECT
    ft.sk_user                       AS sk_user,
    ft.ts_created                    AS ts_ticket_started,
    CAST(ft.sk_ticket AS STRING)     AS sk_ticket,
    COALESCE(ft.sk_contract, -1)     AS sk_contract_ticket,
    CASE
      WHEN (
          (ft.front_or_back = 'front' AND ft.channel IN ('chat', 'call') AND dd.area = 'CX')
          OR dd.department IN ('Offboarding Front')
        )
        AND tx.step_tag = 'rental_offboarding'
        AND tx.motivation IN ('complaint', 'request')
        THEN 'front'
      WHEN dd.department IN ('Atendimento Escalado [OFF] [POS] [BACK]')
        AND ft.channel IN ('email')
        THEN 'back escaladado'
      WHEN dd.department IN ('Agendamento Vistoria Saída [SO]')
        AND CAST(get_json_object(dit.custom_fields, '$["[SO] Time"]') AS VARCHAR(30)) IN ('agendamento_offboarding')
        AND da_last.sk_analyst <> '-1'
        AND ft.channel = 'email'
        AND (
          CASE
            WHEN dit.ticket_via = 'api'
              AND CAST(get_json_object(dit.custom_fields, '$["Taskmaster Task Id"]') AS VARCHAR(30)) IS NOT NULL
              THEN TRUE
            WHEN dit.ticket_via = 'web' THEN TRUE
            ELSE FALSE
          END
        ) IS TRUE
        THEN 'Agendamento Vistoria'
      ELSE 'Outros'
    END AS tipo_ticket
  FROM dw_customer_support.fact_tickets ft
  INNER JOIN dw_customer_support.dim_department dd
    ON ft.sk_main_department = dd.sk_department
  LEFT JOIN dw_customer_support.dim_ticket AS dit
    ON dit.sk_ticket = ft.sk_ticket
  LEFT JOIN dw_customer_support.dim_analyst AS da_last
    ON da_last.sk_analyst = ft.sk_last_analyst
  LEFT JOIN dw_customer_support.dim_taxonomy tx
    ON tx.sk_taxonomy = ft.sk_taxonomy
  WHERE CAST(ft.ts_created AS DATE) >= DATE('2026-04-01')
    AND ft.sk_user <> -1
),

-- Salesforce cases from BPO cases perspective.
salesforce_cases_perspective AS (
  SELECT DISTINCT
    cp.sk_user,
    cp.ts_started                                AS ts_ticket_started,
    CAST(cp.case_number AS STRING)               AS sk_ticket,
    COALESCE(CAST(cp.sk_contract AS BIGINT), -1) AS sk_contract_ticket,
    CASE
      WHEN cp.record_type_name = 'Reagendamento de Vistoria'
        THEN 'Reagendamento de Vistoria'
      WHEN cp.last_team LIKE 'Escalados%'
        THEN 'back escaladado'
    END                                          AS tipo_ticket
  FROM dw_bpo_performance.cases_perspective cp
  WHERE cp.platform = 'SalesForce'
    AND cp.status NOT IN ('CANCELED')
    AND CAST(cp.ts_started AS DATE) >= DATE('2026-04-01')
    AND (
      cp.record_type_name = 'Reagendamento de Vistoria'
      OR cp.last_team LIKE 'Escalados%'
    )
),

tickets AS (
  SELECT * FROM pre_tickets WHERE tipo_ticket <> 'Outros'
  UNION ALL
  SELECT * FROM salesforce_cases_perspective
),

-- Join tickets to enriched terminator using the offboarding time window.
-- Match by contract key or by user (tenant/owner) when contract key is -1.
terminator_with_tickets AS (
  SELECT
    te.id_contract,
    te.ts_created,
    te.spoc_wave,
    te.is_spoc,
    te.team,
    te.id_request,
    te.id_contract_request,
    te.prediction,
    te.probability,
    te.ts_log,
    te.ts_offboarding_start,
    te.ts_last_date_for_target,
    te.is_spoc_eligible_terminator,
    te.is_mediacao,
    t.sk_ticket,
    t.tipo_ticket,
    t.ts_ticket_started
  FROM terminator_enriched te
  LEFT JOIN tickets t
    ON (
      (te.sk_contract = t.sk_contract_ticket AND t.sk_contract_ticket <> -1)
      OR (
        (te.sk_tenant = t.sk_user OR te.sk_owner = t.sk_user)
        AND t.sk_contract_ticket = -1
      )
    )
    AND t.ts_ticket_started BETWEEN te.ts_offboarding_start AND te.ts_last_date_for_target
),

-- Row number per (id_contract, tipo_ticket) to identify duplicate Agendamento Vistoria.
with_rn AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY id_contract, tipo_ticket
      ORDER BY ts_ticket_started
    ) AS rn
  FROM terminator_with_tickets
),

-- Filter: drop first Agendamento Vistoria (only count reagendamentos, rn > 1).
-- No SPOC filter here — terminator spine already guarantees SPOC eligibility.
filtered AS (
  SELECT *
  FROM with_rn
  WHERE tipo_ticket <> 'Agendamento Vistoria'
     OR tipo_ticket IS NULL
     OR (tipo_ticket = 'Agendamento Vistoria' AND rn > 1)
),

-- Aggregate to one row per contract.
target_per_contract AS (
  SELECT
    id_contract,
    ts_created,
    spoc_wave,
    is_spoc,
    team,
    id_request,
    id_contract_request,
    prediction,
    probability,
    ts_log,
    MAX(
      CASE
        WHEN tipo_ticket = 'Agendamento Vistoria' THEN 'Reagendamento de Vistoria'
        WHEN tipo_ticket IS NULL AND is_mediacao = 1 THEN 'mediacao'
        ELSE tipo_ticket
      END
    )                                                           AS tipo_ticket,
    MAX(sk_ticket)                                              AS id_ticket
  FROM filtered
  GROUP BY
    id_contract,
    ts_created,
    spoc_wave,
    is_spoc,
    team,
    id_request,
    id_contract_request,
    prediction,
    probability,
    ts_log
)

SELECT
  id_contract,
  id_request,
  id_contract_request,
  spoc_wave,
  is_spoc,
  team,
  prediction,
  probability,
  id_ticket,
  tipo_ticket,
  ts_created,
  ts_log
FROM target_per_contract
