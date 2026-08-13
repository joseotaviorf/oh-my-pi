-- ================================================================
-- Consórcio Funil Cohort scorecard (deal grain)
-- One row per deal in datalake_consorcio.deal. First-hit timestamps
-- (skip-step COALESCE; contact attempt is a branch), current-position
-- is_* flags, handoff, discarded_from_stage. Built only from
-- deal_stage visits + deal attributes. Cycle times vs
-- dw_public.dim_date belong in metric.
-- Visit timestamps are already America/Sao_Paulo on deal_stage.
-- Full rebuild each run.
-- ================================================================
WITH stage_visits AS (
  SELECT
    deal_stage.id_deal,
    LOWER(deal_stage.stage_name) AS stage_name,
    deal_stage.ts_entered,
    ROW_NUMBER() OVER (
      PARTITION BY deal_stage.id_deal
      ORDER BY deal_stage.ts_entered DESC, CAST(deal_stage.id_stage AS BIGINT) DESC
    ) AS rn,
    LAG(LOWER(deal_stage.stage_name)) OVER (
      PARTITION BY deal_stage.id_deal
      ORDER BY deal_stage.ts_entered, CAST(deal_stage.id_stage AS BIGINT)
    ) AS last_stage
  FROM
    datalake_consorcio.deal_stage AS deal_stage
),
deal_milestones AS (
  SELECT
    id_deal,
    MIN(CASE WHEN stage_name = 'leads' THEN ts_entered END) AS ts_lead,
    MIN(CASE WHEN stage_name = 'tentativa de contato' THEN ts_entered END) AS ts_contact_attempt,
    MIN(CASE WHEN stage_name = 'contato com sucesso' THEN ts_entered END) AS ts_success_contact,
    MIN(CASE WHEN stage_name = 'simulação' THEN ts_entered END) AS ts_simulation_sent,
    MIN(CASE WHEN stage_name = 'simulação aceita' THEN ts_entered END) AS ts_simulation_accepted,
    MIN(CASE WHEN stage_name = 'proposta em negociação' THEN ts_entered END) AS ts_offer_under_negotiation,
    MIN(CASE WHEN stage_name = 'proposta aceita' THEN ts_entered END) AS ts_offer_accepted,
    MIN(CASE WHEN stage_name = 'agendamento de pagamento' THEN ts_entered END) AS ts_payment_scheduled,
    MIN(CASE WHEN stage_name = 'contrato emitido' THEN ts_entered END) AS ts_contract_created,
    MIN(CASE WHEN stage_name = 'venda fechada' THEN ts_entered END) AS ts_closed_deal,
    MIN(CASE WHEN stage_name = 'descarte' THEN ts_entered END) AS ts_discarded
  FROM
    stage_visits
  GROUP BY
    id_deal
),
current_visit AS (
  SELECT
    id_deal,
    last_stage
  FROM
    stage_visits
  WHERE
    rn = 1
)
SELECT
  consorcio_deal.id_deal,
  consorcio_deal.uuid_lead,
  consorcio_deal.current_stage,
  CASE
    WHEN consorcio_deal.current_stage = 'descarte' THEN current_visit.last_stage
  END AS discarded_from_stage,
  CASE
    WHEN COALESCE(
      deal_milestones.ts_lead,
      deal_milestones.ts_success_contact,
      deal_milestones.ts_simulation_sent,
      deal_milestones.ts_simulation_accepted,
      deal_milestones.ts_offer_under_negotiation,
      deal_milestones.ts_offer_accepted,
      deal_milestones.ts_contract_created,
      deal_milestones.ts_payment_scheduled,
      deal_milestones.ts_closed_deal
    ) IS NOT NULL THEN 1
    ELSE 0
  END AS is_lead,
  CASE
    WHEN deal_milestones.ts_contact_attempt IS NOT NULL THEN 1
    ELSE 0
  END AS is_contact_attempted,
  CASE
    WHEN COALESCE(
      deal_milestones.ts_success_contact,
      deal_milestones.ts_simulation_sent,
      deal_milestones.ts_simulation_accepted,
      deal_milestones.ts_offer_under_negotiation,
      deal_milestones.ts_offer_accepted,
      deal_milestones.ts_contract_created,
      deal_milestones.ts_payment_scheduled,
      deal_milestones.ts_closed_deal
    ) IS NOT NULL
      AND consorcio_deal.current_stage NOT IN ('carrinho abandonado', 'leads', 'tentativa de contato') THEN 1
    ELSE 0
  END AS is_success_contact,
  CASE
    WHEN COALESCE(
      deal_milestones.ts_simulation_sent,
      deal_milestones.ts_simulation_accepted,
      deal_milestones.ts_offer_under_negotiation,
      deal_milestones.ts_offer_accepted,
      deal_milestones.ts_contract_created,
      deal_milestones.ts_payment_scheduled,
      deal_milestones.ts_closed_deal
    ) IS NOT NULL
      AND consorcio_deal.current_stage NOT IN (
        'carrinho abandonado',
        'leads',
        'tentativa de contato',
        'contato com sucesso'
      ) THEN 1
    ELSE 0
  END AS is_simulation_sent,
  CASE
    WHEN COALESCE(
      deal_milestones.ts_simulation_accepted,
      deal_milestones.ts_offer_under_negotiation,
      deal_milestones.ts_offer_accepted,
      deal_milestones.ts_contract_created,
      deal_milestones.ts_payment_scheduled,
      deal_milestones.ts_closed_deal
    ) IS NOT NULL
      AND consorcio_deal.current_stage NOT IN (
        'carrinho abandonado',
        'leads',
        'tentativa de contato',
        'contato com sucesso',
        'simulação'
      ) THEN 1
    ELSE 0
  END AS is_simulation_accepted,
  CASE
    WHEN COALESCE(
      deal_milestones.ts_offer_under_negotiation,
      deal_milestones.ts_offer_accepted,
      deal_milestones.ts_contract_created,
      deal_milestones.ts_payment_scheduled,
      deal_milestones.ts_closed_deal
    ) IS NOT NULL
      AND consorcio_deal.current_stage NOT IN (
        'carrinho abandonado',
        'leads',
        'tentativa de contato',
        'contato com sucesso',
        'simulação',
        'simulação aceita'
      ) THEN 1
    ELSE 0
  END AS is_offer_under_negotiation,
  CASE
    WHEN COALESCE(
      deal_milestones.ts_offer_accepted,
      deal_milestones.ts_contract_created,
      deal_milestones.ts_payment_scheduled,
      deal_milestones.ts_closed_deal
    ) IS NOT NULL
      AND consorcio_deal.current_stage NOT IN (
        'carrinho abandonado',
        'leads',
        'tentativa de contato',
        'contato com sucesso',
        'simulação',
        'simulação aceita',
        'proposta em negociação'
      ) THEN 1
    ELSE 0
  END AS is_offer_accepted,
  CASE
    WHEN COALESCE(
      deal_milestones.ts_contract_created,
      deal_milestones.ts_closed_deal
    ) IS NOT NULL
      AND consorcio_deal.current_stage NOT IN (
        'carrinho abandonado',
        'leads',
        'tentativa de contato',
        'contato com sucesso',
        'simulação',
        'simulação aceita',
        'proposta em negociação',
        'proposta aceita'
      ) THEN 1
    ELSE 0
  END AS is_contract_created,
  CASE
    WHEN deal_milestones.ts_closed_deal IS NOT NULL
      AND consorcio_deal.current_stage = 'venda fechada' THEN 1
    ELSE 0
  END AS is_closed_deal,
  CASE
    WHEN consorcio_deal.inside_sales_pipeline = 'SDR IA'
      AND COALESCE(
        deal_milestones.ts_simulation_sent,
        deal_milestones.ts_simulation_accepted,
        deal_milestones.ts_offer_under_negotiation,
        deal_milestones.ts_offer_accepted,
        deal_milestones.ts_contract_created,
        deal_milestones.ts_payment_scheduled,
        deal_milestones.ts_closed_deal
      ) IS NOT NULL
      AND consorcio_deal.current_stage NOT IN (
        'carrinho abandonado',
        'leads',
        'tentativa de contato',
        'contato com sucesso'
      ) THEN 1
    WHEN consorcio_deal.inside_sales_pipeline = 'SIMULATOR IA'
      AND COALESCE(
        deal_milestones.ts_simulation_accepted,
        deal_milestones.ts_offer_under_negotiation,
        deal_milestones.ts_offer_accepted,
        deal_milestones.ts_contract_created,
        deal_milestones.ts_payment_scheduled,
        deal_milestones.ts_closed_deal
      ) IS NOT NULL
      AND consorcio_deal.current_stage NOT IN (
        'carrinho abandonado',
        'leads',
        'tentativa de contato',
        'contato com sucesso',
        'simulação'
      ) THEN 1
    WHEN consorcio_deal.inside_sales_pipeline = 'SDR Humano' THEN 1
    ELSE 0
  END AS is_handoff,
  CASE
    WHEN deal_milestones.ts_discarded IS NOT NULL
      AND consorcio_deal.current_stage = 'descarte' THEN 1
    ELSE 0
  END AS is_discarded,
  consorcio_deal.dt_created,
  COALESCE(
    deal_milestones.ts_lead,
    deal_milestones.ts_success_contact,
    deal_milestones.ts_simulation_sent,
    deal_milestones.ts_simulation_accepted,
    deal_milestones.ts_offer_under_negotiation,
    deal_milestones.ts_offer_accepted,
    deal_milestones.ts_contract_created,
    deal_milestones.ts_payment_scheduled,
    deal_milestones.ts_closed_deal
  ) AS ts_lead,
  deal_milestones.ts_contact_attempt,
  COALESCE(
    deal_milestones.ts_success_contact,
    deal_milestones.ts_simulation_sent,
    deal_milestones.ts_simulation_accepted,
    deal_milestones.ts_offer_under_negotiation,
    deal_milestones.ts_offer_accepted,
    deal_milestones.ts_contract_created,
    deal_milestones.ts_payment_scheduled,
    deal_milestones.ts_closed_deal
  ) AS ts_success_contact,
  COALESCE(
    deal_milestones.ts_simulation_sent,
    deal_milestones.ts_simulation_accepted,
    deal_milestones.ts_offer_under_negotiation,
    deal_milestones.ts_offer_accepted,
    deal_milestones.ts_contract_created,
    deal_milestones.ts_payment_scheduled,
    deal_milestones.ts_closed_deal
  ) AS ts_simulation_sent,
  COALESCE(
    deal_milestones.ts_simulation_accepted,
    deal_milestones.ts_offer_under_negotiation,
    deal_milestones.ts_offer_accepted,
    deal_milestones.ts_contract_created,
    deal_milestones.ts_payment_scheduled,
    deal_milestones.ts_closed_deal
  ) AS ts_simulation_accepted,
  COALESCE(
    deal_milestones.ts_offer_under_negotiation,
    deal_milestones.ts_offer_accepted,
    deal_milestones.ts_contract_created,
    deal_milestones.ts_payment_scheduled,
    deal_milestones.ts_closed_deal
  ) AS ts_offer_under_negotiation,
  COALESCE(
    deal_milestones.ts_offer_accepted,
    deal_milestones.ts_contract_created,
    deal_milestones.ts_payment_scheduled,
    deal_milestones.ts_closed_deal
  ) AS ts_offer_accepted,
  deal_milestones.ts_payment_scheduled,
  COALESCE(
    deal_milestones.ts_contract_created,
    deal_milestones.ts_closed_deal
  ) AS ts_contract_created,
  deal_milestones.ts_closed_deal,
  deal_milestones.ts_discarded,
  CASE
    WHEN consorcio_deal.inside_sales_pipeline = 'SDR IA'
      THEN COALESCE(
        deal_milestones.ts_simulation_sent,
        deal_milestones.ts_simulation_accepted,
        deal_milestones.ts_offer_under_negotiation,
        deal_milestones.ts_offer_accepted,
        deal_milestones.ts_contract_created,
        deal_milestones.ts_payment_scheduled,
        deal_milestones.ts_closed_deal
      )
    WHEN consorcio_deal.inside_sales_pipeline = 'SIMULATOR IA'
      THEN COALESCE(
        deal_milestones.ts_simulation_accepted,
        deal_milestones.ts_offer_under_negotiation,
        deal_milestones.ts_offer_accepted,
        deal_milestones.ts_contract_created,
        deal_milestones.ts_payment_scheduled,
        deal_milestones.ts_closed_deal
      )
    WHEN consorcio_deal.inside_sales_pipeline = 'SDR Humano'
      THEN COALESCE(deal_milestones.ts_lead, deal_milestones.ts_success_contact)
  END AS ts_handoff,
  YEAR(consorcio_deal.dt_created) AS year,
  MONTH(consorcio_deal.dt_created) AS month,
  DAY(consorcio_deal.dt_created) AS day
FROM
  datalake_consorcio.deal AS consorcio_deal
LEFT JOIN
  deal_milestones
    ON deal_milestones.id_deal = CAST(consorcio_deal.id_deal AS STRING)
LEFT JOIN
  current_visit
    ON current_visit.id_deal = CAST(consorcio_deal.id_deal AS STRING)
