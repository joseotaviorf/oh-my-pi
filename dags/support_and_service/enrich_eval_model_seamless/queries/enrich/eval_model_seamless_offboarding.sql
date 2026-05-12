-- eval_model_seamless_offboarding: ground-truth style view for seamless offboarding model evaluation.
-- Grain: one row per distinct combination of termination, optional ticket classification, and model log.
-- Compares who requested termination (SPOC-eligible) with observable contact (tickets / mediation)
-- against users-and-journeys-ml outputs for the same contract.
-- Date window: from 2026-04-01 onward, intersected with the last 6 months from the DAG run date.

-- Users in Post_Contract with offboarding journey step (daily snapshot from SS logic model).
WITH journeys AS (
  SELECT
    id_user,
    id_snapshot,
    COALESCE(LOWER(tenant_journey_step), 'default') AS tenant_journey_step,
    COALESCE(LOWER(landlord_journey_step), 'default') AS landlord_journey_step
  FROM datalake_ss_logic_model.user_ss_metrics
  WHERE CAST(id_snapshot AS BIGINT) >= 20260401
    AND CAST(id_snapshot AS BIGINT) >= CAST(
      DATE_FORMAT(ADD_MONTHS(CURRENT_DATE(), -6), 'yyyyMMdd') AS BIGINT
    )
    AND (
      tenant_persona_step = 'Post_Contract' OR
      landlord_persona_step = 'Post_Contract'
    )
),

-- Calendar day + user when journey indicates offboarding for tenant or landlord.
contract_people_timeline AS (
  SELECT
    TO_DATE(CAST(id_snapshot AS STRING), 'yyyyMMdd') AS day_ref,
    CAST(id_user AS INTEGER) AS id_user
  FROM journeys
  WHERE tenant_journey_step = 'offboarding'
     OR landlord_journey_step = 'offboarding'
),

-- Classify Customer Support (enrich) tickets that count as offboarding-related contact (same day as snapshot).
-- Uses datalake_customer_support.tickets (not DW) and Zendesk clean for via_channel on scheduling rules.
pre_tickets AS (
  SELECT
    CAST(ft.sk_user AS INTEGER) AS id_user,
    CAST(ft.sk_ticket AS STRING) AS id_ticket,
    COALESCE(ft.sk_contract, -1) AS id_contract_ticket,
    CAST(ft.ts_created AS DATE) AS day_ticket_started,
    CASE WHEN ((ft.front_or_back = 'front' 
      AND ft.channel IN ('chat','call') 
      AND dd.area = 'CX') OR dd.department IN ('Offboarding Front')) 
      AND (tx.step_tag = 'rental_offboarding') 
      AND (tx.motivation in ('complaint', 'request')) THEN 'front'
      WHEN dd.department IN ('Atendimento Escalado [OFF] [POS] [BACK]') AND ft.channel IN ('email') THEN 'back escaladado'
      WHEN dd.department IN ('Offboarding Reparos [OFF] [POS] [BACK]') AND ft.channel IN ('email') THEN 'mediacao'
      WHEN (dd.department IN ('Agendamento Vistoria Saída [SO]')
       AND CAST(get_json_object(dit.custom_fields, '$["[SO] Time"]') AS VARCHAR(30)) IN ('agendamento_offboarding')
       AND da_last.sk_analyst <> '-1'
       AND ft.channel = 'email'
       AND (CASE WHEN dit.ticket_via = 'api' 
       AND CAST(get_json_object(dit.custom_fields, '$["Taskmaster Task Id"]') AS VARCHAR(30)) is not NULL THEN TRUE WHEN dit.ticket_via = 'web' THEN TRUE ELSE FALSE END) = TRUE) THEN 'Agendamento Vistoria' 
       ELSE NULL END tipo_ticket
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
    AND CAST(ft.ts_created AS DATE) >= ADD_MONTHS(CURRENT_DATE(), -6)
),

-- Salesforce mediation cases as another contact signal (no user key; contract-level).
salesforce AS (
  SELECT DISTINCT
    NULL AS id_user,
    CAST(case_number AS STRING) AS id_ticket,
    CAST(c.id_contract AS INT) AS id_contract_ticket,
    CAST(c.ts_created AS DATE) AS day_ticket_started,
    CASE WHEN rt.record_type_name IN ('Mediação') AND c.omni_channel_queue NOT IN ('Squad 7 - Mediação') THEN 'mediacao' 
         WHEN rt.record_type_name IN ('Reagendamento de Vistoria') THEN 'Agendamento Vistoria' ELSE NULL END AS tipo_ticket
  FROM datalake_salesforce_clean.cases AS c
  INNER JOIN datalake_salesforce_clean.record_types AS rt
     ON rt.id_record_type = c.id_record_type
  WHERE c.is_deleted = FALSE
    AND CAST(c.ts_created AS DATE) >= DATE('2026-04-01')
    AND CAST(c.ts_created AS DATE) >= ADD_MONTHS(CURRENT_DATE(), -6)
    AND c.case_status NOT IN ('CANCELED')
),

tickets AS (
  SELECT * FROM pre_tickets
  UNION ALL
  SELECT * FROM salesforce
),

-- Map offboarding users to contracts via enrich rent flows (tenant prospect or owner).
pre_final AS (
  SELECT DISTINCT
    COALESCE(l.id_contract, -1) AS id_contract,
    contract_people_timeline.id_user,
    contract_people_timeline.day_ref
  FROM contract_people_timeline
  JOIN datalake_rent_flows.rent_flows l
    ON contract_people_timeline.id_user = l.id_tenant_prospect
    OR contract_people_timeline.id_user = l.id_owner
  WHERE l.id_tenant_prospect IS NOT NULL
     OR l.id_owner IS NOT NULL
),

-- Same-day ticket match OR ticket within 10 days of snapshot (with contract guards on second branch).
final AS (
  SELECT
    pre_final.id_contract,
    tipo_ticket,
    tickets.id_contract_ticket,
    tickets.id_ticket
  FROM pre_final
  LEFT JOIN tickets
    ON (pre_final.id_user = tickets.id_user OR (pre_final.id_contract = tickets.id_contract_ticket AND tickets.id_contract_ticket <> -1))
   AND (tipo_ticket IS NOT NULL)
   AND pre_final.day_ref = tickets.day_ticket_started

  UNION ALL

  SELECT
    pre_final.id_contract,
    tipo_ticket,
    tickets.id_contract_ticket,
    tickets.id_ticket
  FROM pre_final
  INNER JOIN tickets
    ON (pre_final.id_user = tickets.id_user OR (pre_final.id_contract = tickets.id_contract_ticket AND tickets.id_contract_ticket <> -1))
   AND (tipo_ticket IS NOT NULL)
   AND tickets.day_ticket_started BETWEEN day_ref AND DATE_ADD(day_ref, 10)
   WHERE (id_contract_ticket = id_contract) OR id_contract_ticket IS NULL OR id_contract_ticket = -1
),

-- Emlio logs for the ML service used by seamless / journeys scoring.
model_infos AS (
  SELECT
    get_json_object(inputs, '$.request_id') AS id_request,
    get_json_object(inputs, '$.contract_id') AS id_contract_request,
    get_json_object(outputs, '$.prediction') AS prediction,
    get_json_object(outputs, '$.probability') AS probability,
    ts_log
  FROM datalake_emlio_clean.emlio_logs
  WHERE id_service = 'users-and-journeys-ml-service'
    AND CAST(ts_log AS DATE) >= DATE('2026-04-01')
    AND CAST(ts_log AS DATE) >= ADD_MONTHS(CURRENT_DATE(), -6)
),

-- SPOC-eligible terminations joined to model inference rows when id_request matches termination id.
terminator AS (
  SELECT
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

-- Single exit-inspection scheduling ticket per contract: drop tipo_ticket when rule would over-count.
agendamento_vistoria AS (
  SELECT
    id_contract,
    COUNT(DISTINCT id_ticket) qtd_agendamento
  FROM final
  WHERE tipo_ticket = 'Agendamento Vistoria'
  GROUP BY id_contract
  HAVING COUNT(DISTINCT id_ticket) <= 1
),

final_with_counts AS (
  SELECT
    t.*,
    CASE WHEN qtd_agendamento IS NOT NULL AND f.tipo_ticket = 'Agendamento Vistoria' THEN NULL ELSE f.tipo_ticket END tipo_ticket
  FROM terminator t
  LEFT JOIN final f
    ON t.id_contract = f.id_contract
  LEFT JOIN agendamento_vistoria a
    ON t.id_contract = a.id_contract
),

-- Per contract: count of non-null tipo_ticket rows (used only in WHERE, not exposed as output).
cleaned_data AS (
  SELECT
    *,
    COUNT(tipo_ticket) OVER (PARTITION BY id_contract) AS is_ticket_valido
  FROM final_with_counts
)

SELECT DISTINCT
  id_contract,
  id_request,
  id_contract_request,
  spoc_wave,
  is_spoc,
  team,
  prediction,
  probability,
  CASE WHEN tipo_ticket = 'Agendamento Vistoria' THEN 'Reagendamento de Vistoria' ELSE tipo_ticket END AS tipo_ticket,
  ts_created,
  ts_log
FROM cleaned_data
WHERE
  (is_ticket_valido > 0 AND tipo_ticket IS NOT NULL)
  OR
  (is_ticket_valido = 0)
