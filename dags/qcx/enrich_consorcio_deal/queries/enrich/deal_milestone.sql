-- ================================================================
-- Consórcio Funil Cohort scorecard (deal grain)
-- One row per deal in datalake_consorcio.deal. First-hit timestamps
-- (skip-step COALESCE; contact attempt is a branch), current-position
-- is_* flags, handoff, discarded_from_stage, plus materialized
-- business-day cycle times vs dw_public.dim_date.
-- Visit timestamps are already America/Sao_Paulo on deal_stage.
-- Full rebuild each run.
--
-- Funnel: lead -> success contact -> simulation sent -> simulation
-- accepted -> offer under negotiation -> offer accepted ->
-- contract created -> closed deal. Branches: contact attempt,
-- handoff, discarded.
-- The 'agendamento de pagamento' (payment scheduled) stage has been
-- retired and is no longer read from deal_stage.
--
-- Cycle times use cumulative business-day counters instead of one
-- correlated subquery per metric:
--   bd_incl(d) = # business days in [range_start, d]
--   bd_excl(d) = # business days in [range_start, d-1]
--   # business days in [s, e] = bd_incl(e) - bd_excl(s)
-- The calendar is scanned once and broadcast as two maps.
--
-- NOTE: aging_opened_leads and days_in_current_stage (last two
-- columns) are relative to D-1. Every other metric is immutable once the
-- milestone is reached.
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
),

-- ----------------------------------------------------------------
-- Business-day calendar: one scan, two cumulative counters.
-- Static bound so the window does not shift between runs. Results
-- are differences within the same map, so the lower bound cancels
-- out; an endpoint outside the window yields NULL, never a wrong
-- number.
-- ----------------------------------------------------------------
business_day_counters AS (
  SELECT
    date,
    SUM(CASE WHEN is_brz_business_day THEN 1 ELSE 0 END)
      OVER (ORDER BY date) AS bd_incl,
    SUM(CASE WHEN is_brz_business_day THEN 1 ELSE 0 END)
      OVER (ORDER BY date)
      - CASE WHEN is_brz_business_day THEN 1 ELSE 0 END AS bd_excl
  FROM
    dw_public.dim_date
  WHERE
    date BETWEEN DATE '2025-08-01' AND DATE '2035-12-31'
),
business_day_maps AS (
  SELECT
    MAP_FROM_ENTRIES(COLLECT_LIST(STRUCT(date, bd_incl))) AS incl,
    MAP_FROM_ENTRIES(COLLECT_LIST(STRUCT(date, bd_excl))) AS excl
  FROM business_day_counters
),

-- ----------------------------------------------------------------
-- Milestone projection, wrapped as a CTE so the skip-step COALESCE
-- chains are written once and the cycle-time expressions can
-- reference the resolved ts_* / is_* by name.
-- ----------------------------------------------------------------
deal_funnel_scorecard AS (
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
    consorcio_deal.ts_deal_created,
    consorcio_deal.dt_created,
    COALESCE(
      deal_milestones.ts_lead,
      deal_milestones.ts_success_contact,
      deal_milestones.ts_simulation_sent,
      deal_milestones.ts_simulation_accepted,
      deal_milestones.ts_offer_under_negotiation,
      deal_milestones.ts_offer_accepted,
      deal_milestones.ts_contract_created,
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
      deal_milestones.ts_closed_deal
    ) AS ts_success_contact,
    COALESCE(
      deal_milestones.ts_simulation_sent,
      deal_milestones.ts_simulation_accepted,
      deal_milestones.ts_offer_under_negotiation,
      deal_milestones.ts_offer_accepted,
      deal_milestones.ts_contract_created,
      deal_milestones.ts_closed_deal
    ) AS ts_simulation_sent,
    COALESCE(
      deal_milestones.ts_simulation_accepted,
      deal_milestones.ts_offer_under_negotiation,
      deal_milestones.ts_offer_accepted,
      deal_milestones.ts_contract_created,
      deal_milestones.ts_closed_deal
    ) AS ts_simulation_accepted,
    COALESCE(
      deal_milestones.ts_offer_under_negotiation,
      deal_milestones.ts_offer_accepted,
      deal_milestones.ts_contract_created,
      deal_milestones.ts_closed_deal
    ) AS ts_offer_under_negotiation,
    COALESCE(
      deal_milestones.ts_offer_accepted,
      deal_milestones.ts_contract_created,
      deal_milestones.ts_closed_deal
    ) AS ts_offer_accepted,
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
          deal_milestones.ts_closed_deal
        )
      WHEN consorcio_deal.inside_sales_pipeline = 'SIMULATOR IA'
        THEN COALESCE(
          deal_milestones.ts_simulation_accepted,
          deal_milestones.ts_offer_under_negotiation,
          deal_milestones.ts_offer_accepted,
          deal_milestones.ts_contract_created,
          deal_milestones.ts_closed_deal
        )
      WHEN consorcio_deal.inside_sales_pipeline = 'SDR Humano'
        THEN COALESCE(deal_milestones.ts_lead, deal_milestones.ts_success_contact)
    END AS ts_handoff,
    -- helper column: feeds days_in_current_stage only, dropped from
    -- the final projection
    consorcio_deal.ts_current_stage_started AS _ts_current_stage_started
  FROM
    datalake_consorcio.deal AS consorcio_deal
  LEFT JOIN
    deal_milestones
      ON deal_milestones.id_deal = CAST(consorcio_deal.id_deal AS STRING)
  LEFT JOIN
    current_visit
      ON current_visit.id_deal = CAST(consorcio_deal.id_deal AS STRING)
),

-- ----------------------------------------------------------------
-- Calendar lookups, resolved once per deal.
--
-- Pulling these out of the metric expressions is what makes the null
-- contract enforceable. A lookup is NULL in exactly two cases: the
-- timestamp is NULL, or its date falls outside the calendar window.
-- Both must yield a NULL metric, never 0 — and because Spark's
-- GREATEST *skips* nulls (GREATEST(0, NULL) = 0, unlike Trino, which
-- propagates), that cannot be left to GREATEST. Each metric below
-- therefore guards on the lookups being non-null before applying the
-- floor, which covers both failure modes with one condition.
-- ----------------------------------------------------------------
deal_calendar_lookups AS (
  SELECT
    base.id_deal,
    TRY_ELEMENT_AT(business_day_maps.incl, DATE_SUB(CURRENT_DATE(), 1)) AS incl_yesterday,
    TRY_ELEMENT_AT(business_day_maps.excl, CAST(deal_funnel_scorecard.ts_deal_created             AS DATE)) AS excl_deal_created,
    TRY_ELEMENT_AT(business_day_maps.excl, CAST(deal_funnel_scorecard._ts_current_stage_started AS DATE)) AS excl_current_stage_started,
    TRY_ELEMENT_AT(business_day_maps.incl, CAST(deal_funnel_scorecard.ts_lead                    AS DATE)) AS incl_lead,
    TRY_ELEMENT_AT(business_day_maps.incl, CAST(deal_funnel_scorecard.ts_contact_attempt         AS DATE)) AS incl_contact_attempt,
    TRY_ELEMENT_AT(business_day_maps.incl, CAST(deal_funnel_scorecard.ts_success_contact          AS DATE)) AS incl_success_contact,
    TRY_ELEMENT_AT(business_day_maps.incl, CAST(deal_funnel_scorecard.ts_simulation_sent          AS DATE)) AS incl_simulation_sent,
    TRY_ELEMENT_AT(business_day_maps.incl, CAST(deal_funnel_scorecard.ts_simulation_accepted      AS DATE)) AS incl_simulation_accepted,
    TRY_ELEMENT_AT(business_day_maps.incl, CAST(deal_funnel_scorecard.ts_offer_under_negotiation  AS DATE)) AS incl_offer_under_negotiation,
    TRY_ELEMENT_AT(business_day_maps.incl, CAST(deal_funnel_scorecard.ts_offer_accepted           AS DATE)) AS incl_offer_accepted,
    TRY_ELEMENT_AT(business_day_maps.incl, CAST(deal_funnel_scorecard.ts_contract_created         AS DATE)) AS incl_contract_created,
    TRY_ELEMENT_AT(business_day_maps.incl, CAST(deal_funnel_scorecard.ts_closed_deal              AS DATE)) AS incl_closed_deal,
    TRY_ELEMENT_AT(business_day_maps.incl, CAST(deal_funnel_scorecard.ts_handoff                  AS DATE)) AS incl_handoff,
    TRY_ELEMENT_AT(business_day_maps.incl, CAST(deal_funnel_scorecard.ts_discarded                AS DATE)) AS incl_discarded
  FROM deal_funnel_scorecard
  CROSS JOIN business_day_maps
)

SELECT
  deal_funnel_scorecard.id_deal,
  deal_funnel_scorecard.uuid_lead,
  deal_funnel_scorecard.current_stage,
  deal_funnel_scorecard.discarded_from_stage,
  deal_funnel_scorecard.is_lead,
  deal_funnel_scorecard.is_contact_attempted,
  deal_funnel_scorecard.is_success_contact,
  deal_funnel_scorecard.is_simulation_sent,
  deal_funnel_scorecard.is_simulation_accepted,
  deal_funnel_scorecard.is_offer_under_negotiation,
  deal_funnel_scorecard.is_offer_accepted,
  deal_funnel_scorecard.is_contract_created,
  deal_funnel_scorecard.is_closed_deal,
  deal_funnel_scorecard.is_handoff,
  deal_funnel_scorecard.is_discarded,
  deal_funnel_scorecard.ts_deal_created,
  deal_funnel_scorecard.dt_created,
  deal_funnel_scorecard.ts_lead,
  deal_funnel_scorecard.ts_contact_attempt,
  deal_funnel_scorecard.ts_success_contact,
  deal_funnel_scorecard.ts_simulation_sent,
  deal_funnel_scorecard.ts_simulation_accepted,
  deal_funnel_scorecard.ts_offer_under_negotiation,
  deal_funnel_scorecard.ts_offer_accepted,
  deal_funnel_scorecard.ts_contract_created,
  deal_funnel_scorecard.ts_closed_deal,
  deal_funnel_scorecard.ts_discarded,
  deal_funnel_scorecard.ts_handoff,
  -- ----------------------------------------------------------------
  -- Business-day cycle times. Every column below has the same shape:
  --
  --     GREATEST(0, incl[END date] - excl[START date] - 1)
  --
  -- incl[d] = business days up to and including d
  -- excl[d] = business days up to d - 1
  -- so the difference is the inclusive business-day count of
  -- [START, END]; the -1 makes a same-day transition 0, and GREATEST
  -- floors out-of-order timestamps at 0 instead of going negative.
  --
  -- Each metric is NULL unless all three conditions hold: is_*
  -- gates are 1 AND both calendar lookups resolved. The lookup guards
  -- are load-bearing, not defensive noise — Spark's GREATEST skips
  -- nulls, so without them a missing timestamp or an out-of-window
  -- date would publish 0, indistinguishable from a same-day
  -- conversion. is_handoff is the live case: it is unconditionally 1
  -- for the SDR Humano track, while ts_handoff can still be NULL when
  -- both leads and contato com sucesso were skipped.
  -- ----------------------------------------------------------------

  -- ===== from deal creation =====================================
  -- Anchored on ts_deal_created and consider the difference in business days
  -- from the deal creation until the deal reached that specific stage, or, if if skipped
  -- that stage for some reason, the first stage after
  CASE
    WHEN deal_funnel_scorecard.is_lead = 1
      AND deal_calendar_lookups.incl_lead IS NOT NULL
      AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_lead - deal_calendar_lookups.excl_deal_created - 1)
  END AS business_days_from_created_to_lead,
  CASE
    WHEN deal_funnel_scorecard.is_contact_attempted = 1
      AND deal_calendar_lookups.incl_contact_attempt IS NOT NULL
      AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_contact_attempt - deal_calendar_lookups.excl_deal_created - 1)
  END AS business_days_from_created_to_contact_attempt,
  CASE
    WHEN deal_funnel_scorecard.is_success_contact = 1
      AND deal_calendar_lookups.incl_success_contact IS NOT NULL
      AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_success_contact - deal_calendar_lookups.excl_deal_created - 1)
  END AS business_days_from_created_to_success_contact,
  CASE
    WHEN deal_funnel_scorecard.is_simulation_sent = 1
      AND deal_calendar_lookups.incl_simulation_sent IS NOT NULL
      AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_simulation_sent - deal_calendar_lookups.excl_deal_created - 1)
  END AS business_days_from_created_to_simulation_sent,
  CASE
    WHEN deal_funnel_scorecard.is_simulation_accepted = 1
      AND deal_calendar_lookups.incl_simulation_accepted IS NOT NULL
      AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_simulation_accepted - deal_calendar_lookups.excl_deal_created - 1)
  END AS business_days_from_created_to_simulation_accepted,
  CASE
    WHEN deal_funnel_scorecard.is_offer_under_negotiation = 1
      AND deal_calendar_lookups.incl_offer_under_negotiation IS NOT NULL
      AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_offer_under_negotiation - deal_calendar_lookups.excl_deal_created - 1)
  END AS business_days_from_created_to_offer_under_negotiation,
  CASE
    WHEN deal_funnel_scorecard.is_offer_accepted = 1
      AND deal_calendar_lookups.incl_offer_accepted IS NOT NULL
      AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_offer_accepted - deal_calendar_lookups.excl_deal_created - 1)
  END AS business_days_from_created_to_offer_accepted,
  CASE
    WHEN deal_funnel_scorecard.is_contract_created = 1
      AND deal_calendar_lookups.incl_contract_created IS NOT NULL
      AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_contract_created - deal_calendar_lookups.excl_deal_created - 1)
  END AS business_days_from_created_to_contract_created,
  CASE
    WHEN deal_funnel_scorecard.is_closed_deal = 1
      AND deal_calendar_lookups.incl_closed_deal IS NOT NULL
      AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_closed_deal - deal_calendar_lookups.excl_deal_created - 1)
  END AS business_days_from_created_to_closed_deal,
  CASE
    WHEN deal_funnel_scorecard.is_handoff = 1
      AND deal_calendar_lookups.incl_handoff IS NOT NULL
      AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_handoff - deal_calendar_lookups.excl_deal_created - 1)
  END AS business_days_from_created_to_handoff,
  CASE
    WHEN deal_funnel_scorecard.is_discarded = 1
      AND deal_calendar_lookups.incl_discarded IS NOT NULL
      AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_discarded - deal_calendar_lookups.excl_deal_created - 1)
  END AS business_days_from_created_to_discarded,

  -- ===== as of the run date (stale between rebuilds) =============
  -- These two float with D-1 instead of being fixed once a
  -- milestone is reached.
  CASE
    WHEN deal_funnel_scorecard.current_stage NOT IN ('venda fechada', 'descarte', 'carrinho abandonado')
        AND deal_calendar_lookups.incl_yesterday IS NOT NULL
        AND deal_calendar_lookups.excl_deal_created IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_yesterday - deal_calendar_lookups.excl_deal_created - 1)
  END AS aging_opened_leads,

  -- no is_* gate, but still NULL if either lookup misses
  CASE
    WHEN deal_calendar_lookups.incl_yesterday IS NOT NULL
      AND deal_calendar_lookups.excl_current_stage_started IS NOT NULL
    THEN GREATEST(0, deal_calendar_lookups.incl_yesterday - deal_calendar_lookups.excl_current_stage_started - 1)
  END AS days_in_current_stage,

  -- ===== partitions (must remain the last columns) ===============
  YEAR(deal_funnel_scorecard.dt_created)  AS year,
  MONTH(deal_funnel_scorecard.dt_created) AS month,
  DAY(deal_funnel_scorecard.dt_created)   AS day

FROM deal_funnel_scorecard
LEFT JOIN deal_calendar_lookups
  ON deal_calendar_lookups.id_deal = deal_funnel_scorecard.id_deal
