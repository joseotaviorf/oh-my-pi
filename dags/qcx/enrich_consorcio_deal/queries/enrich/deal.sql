-- ================================================================
-- Consórcio deal entity (current CRM state, deal grain)
-- One row per unique Consórcio deal at its latest HubSpot stage:
-- identity, attribution, ownership, C2W, qualifier, feedback,
-- simulation aggregates, current_stage. Funnel path lives in
-- deal_stage; Funil Cohort is_*/ts_* rollup lives in deal_milestone.
-- Pipeline 737631007. Timestamps in America/Sao_Paulo.
-- Full rebuild each run.
--
-- Attribution lookups are sourced from Google Sheets in
-- datalake_gsheets_clean: consorcio_origin_mapping (utm_source ->
-- origin), consorcio_segment_mapping (utm_campaign -> segment) and
-- consorcio_inside_sales_operation (analyst relationships), all of
-- which replace hard-coded CTEs. None of the three has a primary key,
-- so each is deduped to one row per key before joining.
--
-- The inside-sales sheet holds one row per analyst RELATIONSHIP: a
-- promotion or a supervisor change closes the old row (dt_ended) and
-- opens a new one. Analyst attribution is therefore resolved as of
-- the deal's creation date, not from the analyst's current row.
--
-- Resolution rules for team / supervisor_name / analyst_role:
--   1. Deal created inside [dt_created, dt_ended] -> that row.
--   2. Deal created before the analyst's first dt_created
--      -> the earliest row (back-fills history the sheet predates).
--   3. Deal created after the analyst's last dt_ended (analyst left,
--      deal still assigned to them) -> team and analyst_role carried
--      forward from the last row; supervisor_name pinned to 'other'.
--   4. A blank dt_created means "in effect from the beginning"
--      (floored to 1900-01-01), so rule 1 covers it.
--   5. Blank dt_ended means the relationship is open (9999-12-31).
-- analyst_name is NOT time-dependent — it is keyed on the owner id
-- alone, and is NULL when the owner has no row in the sheet.
-- ================================================================
WITH
-- ----------------------------------------------------------------
-- Attribution maps, now sourced from Google Sheets instead of inline
-- VALUES. Both sheets are two-column key/value lookups maintained by
-- the team. Keys are trimmed and blank-to-NULL'd, and each is deduped
-- to one row per key so a duplicated sheet row cannot fan out the
-- deal grain (a hand-maintained sheet has no primary key).
-- ----------------------------------------------------------------
origin_mapping AS (
  SELECT
    NULLIF(TRIM(utm_source), '') AS utm_source,
    MAX(NULLIF(TRIM(origin), '')) AS origin
  FROM
    datalake_gsheets_clean.consorcio_origin_mapping
  WHERE
    NULLIF(TRIM(utm_source), '') IS NOT NULL
  GROUP BY
    NULLIF(TRIM(utm_source), '')
),
segment_mapping AS (
  SELECT
    NULLIF(TRIM(utm_campaign), '') AS utm_campaign,
    MAX(NULLIF(TRIM(segment), '')) AS segment
  FROM
    datalake_gsheets_clean.consorcio_segment_mapping
  WHERE
    NULLIF(TRIM(utm_campaign), '') IS NOT NULL
  GROUP BY
    NULLIF(TRIM(utm_campaign), '')
),

-- ----------------------------------------------------------------
-- Inside-sales operation sheet: one row per analyst relationship.
-- Everything arrives as VARCHAR and "empty" is '' rather than NULL,
-- so every column is trimmed and NULLIF'd before casting.
-- The sheet's dt_created/dt_ended are RELATIONSHIP dates and are
-- renamed here to dt_relationship_start/_end so they cannot be
-- confused with the deal's own dt_created further down.
-- ----------------------------------------------------------------
inside_sales_operation AS (
  SELECT
    NULLIF(TRIM(id_hubspot_owner), '') AS id_owner,
    NULLIF(TRIM(analyst_name), '')     AS analyst_name,
    NULLIF(TRIM(team), '')             AS team,
    NULLIF(TRIM(supervisor), '')       AS supervisor_name,
    NULLIF(TRIM(`role`), '')           AS analyst_role,
    -- blank dt_created = relationship in effect from the beginning
    COALESCE(
      TRY_CAST(NULLIF(TRIM(dt_created), '') AS DATE),
      DATE('1900-01-01')
    ) AS dt_relationship_start,
    -- blank dt_ended = relationship still open
    COALESCE(
      TRY_CAST(NULLIF(TRIM(dt_ended), '') AS DATE),
      DATE('9999-12-31')
    ) AS dt_relationship_end
  FROM
    datalake_gsheets_clean.consorcio_inside_sales_operation
  WHERE
    NULLIF(TRIM(id_hubspot_owner), '') IS NOT NULL
),

-- HubSpot fallback for analyst_name ONLY, used when the owner has no
-- row in the sheet. team / supervisor_name / analyst_role stay NULL in
-- that case — the sheet is the sole source for the temporal fields.
-- Note: archived owners have an empty teams array, so the Consorcio
-- team filter below does not recover them.
owner_name AS (
  SELECT
    id_owner,
    MAX(analyst_name) AS analyst_name
  FROM (
    SELECT DISTINCT
      hubspot_owner.id_owner,
      CONCAT(hubspot_owner.first_name, ' ', hubspot_owner.last_name) AS analyst_name
    FROM
      datalake_hubspot_clean.owner AS hubspot_owner
    WHERE
      ELEMENT_AT(hubspot_owner.teams, 1).name LIKE '%Consorcio%'
      AND hubspot_owner.first_name IS NOT NULL
      AND hubspot_owner.first_name <> ''
  ) AS consorcio_owner
  GROUP BY
    id_owner
),

-- analyst_name is keyed on the owner id only, not on the period:
-- collapses the multi-relationship analysts to one name.
analyst_identity AS (
  SELECT
    id_owner,
    MAX(analyst_name) AS analyst_name
  FROM
    inside_sales_operation
  GROUP BY
    id_owner
),

-- first / last relationship per analyst, for the out-of-range rules
analyst_relationship_bounds AS (
  SELECT
    id_owner,
    MIN(dt_relationship_start) AS dt_first_start,
    MAX(dt_relationship_end) AS dt_last_end
  FROM
    inside_sales_operation
  GROUP BY
    id_owner
),
analyst_first_relationship AS (
  SELECT
    id_owner,
    team,
    supervisor_name,
    analyst_role
  FROM (
    SELECT
      id_owner,
      team,
      supervisor_name,
      analyst_role,
      ROW_NUMBER() OVER (
        PARTITION BY id_owner
        ORDER BY dt_relationship_start ASC, dt_relationship_end ASC
      ) AS rn_first
    FROM
      inside_sales_operation
  ) AS ranked_first
  WHERE
    rn_first = 1
),
analyst_last_relationship AS (
  SELECT
    id_owner,
    team,
    analyst_role
  FROM (
    SELECT
      id_owner,
      team,
      analyst_role,
      ROW_NUMBER() OVER (
        PARTITION BY id_owner
        ORDER BY dt_relationship_end DESC, dt_relationship_start DESC
      ) AS rn_last
    FROM
      inside_sales_operation
  ) AS ranked_last
  WHERE
    rn_last = 1
),
simulation_agg AS (
  SELECT
    consorcio_simulation.id_lead,
    MIN(
      FROM_UTC_TIMESTAMP(consorcio_simulation.ts_created, 'America/Sao_Paulo')
    ) AS first_simulation_at,
    MAX(
      FROM_UTC_TIMESTAMP(consorcio_simulation.ts_created, 'America/Sao_Paulo')
    ) AS last_simulation_at,
    COUNT(*) AS total_simulations,
    MIN_BY(
      consorcio_simulation.credit_value, consorcio_simulation.ts_created
    ) AS first_simulation_credit_value,
    MAX_BY(
      consorcio_simulation.credit_value, consorcio_simulation.ts_created
    ) AS last_simulation_credit_value,
    ROUND(
      AVG(
        consorcio_simulation.credit_value
      ),
      2
    ) AS avg_simulation_credit_value
  FROM
    datalake_consorcio_clean.simulation AS consorcio_simulation
  GROUP BY
    consorcio_simulation.id_lead
),
lead_created AS (
  SELECT
    consorcio_lead.uuid AS uuid_lead,
    MIN(
      FROM_UTC_TIMESTAMP(consorcio_lead.ts_created, 'America/Sao_Paulo')
    ) AS ts_lead_created
  FROM
    datalake_consorcio_clean.lead AS consorcio_lead
  WHERE
    consorcio_lead.uuid IS NOT NULL
  GROUP BY
    consorcio_lead.uuid
),
base_all AS (
  SELECT
    hubspot_deal_stage.id_deal,
    hubspot_deal_stage.id_stage,
    LOWER(hubspot_stage.label) AS stage_name,
    hubspot_deal_stage.id_pipeline,
    hubspot_deal.id_hubspot_owner,
    FROM_UTC_TIMESTAMP(hubspot_deal.ts_created, 'America/Sao_Paulo') AS ts_deal_created,
    FROM_UTC_TIMESTAMP(hubspot_deal_stage.ts_stage_started, 'America/Sao_Paulo') AS ts_stage_started,
    hubspot_deal.consorcio_id_lead AS uuid_lead,
    hubspot_deal.consorcio_id_device AS id_device,
    hubspot_deal.deal_name,
    hubspot_deal.consorcio_phone_number AS phone_number,
    hubspot_deal.consorcio_utm_source AS utm_source,
    hubspot_deal.consorcio_utm_medium AS utm_medium,
    hubspot_deal.consorcio_utm_campaign AS utm_campaign,
    hubspot_deal.consorcio_utm_content AS utm_content,
    hubspot_deal.consorcio_utm_term AS utm_term,
    hubspot_deal.consorcio_inside_sales_pipeline,
    hubspot_deal.consorcio_discard_reason,
    hubspot_deal.consorcio_forms_origin,
    hubspot_deal.consorcio_lead_priority,
    hubspot_deal.consorcio_quota_amount,
    hubspot_deal.consorcio_installment_type,
    hubspot_deal.consorcio_channel_origin,
    hubspot_deal.consorcio_deal_duplicado AS duplication_status,
    hubspot_deal.amount,
    hubspot_deal.consorcio_abandoned_cart_template_sent,
    hubspot_deal.consorcio_negotiation_value,
    hubspot_deal.consorcio_blip_agent_inactivity,
    hubspot_deal.consorcio_bamaq_proposal_codes,
    hubspot_deal.consorcio_template_first_contact,
    hubspot_deal.consorcio_template_last_contact,
    hubspot_deal.consorcio_group,
    hubspot_deal.consorcio_user_first_message_reply,
    hubspot_deal.consorcio_entered_rehabilitation,
    hubspot_deal.consorcio_rehabilitation_exit_reason,
    hubspot_deal.consorcio_rehabilitation_variant,
    hubspot_deal.consorcio_rehabilitation_trigger_count,
    hubspot_deal.consorcio_entered_churn,
    hubspot_deal.consorcio_agent_simulation_value,
    TRY_CAST(GET_JSON_OBJECT(hubspot_deal.consorcio_feedback_survey, '$.nota') AS INTEGER) AS feedback_score,
    ARRAY_JOIN(
      FROM_JSON(
        GET_JSON_OBJECT(hubspot_deal.consorcio_feedback_survey, '$.beneficios'),
        'ARRAY<STRING>'
      ),
      ', '
    ) AS feedback_benefits,
    NULLIF(GET_JSON_OBJECT(hubspot_deal.consorcio_feedback_survey, '$.comentario'), '') AS feedback_comment,
    NULLIF(GET_JSON_OBJECT(hubspot_deal.consorcio_feedback_survey, '$.autoriza_contato'), '') AS is_feedback_contact_allowed,
    GET_JSON_OBJECT(consorcio_lead.metadata, '$.customerJourney') AS customer_journey,
    NULLIF(GET_JSON_OBJECT(hubspot_deal.consorcio_conrado_qualificador_responses, '$.goal'), '') AS qualifier_goal,
    NULLIF(GET_JSON_OBJECT(hubspot_deal.consorcio_conrado_qualificador_responses, '$.investmentType'), '') AS qualifier_investment_type,
    NULLIF(GET_JSON_OBJECT(hubspot_deal.consorcio_conrado_qualificador_responses, '$.reason'), '') AS qualifier_reason,
    NULLIF(GET_JSON_OBJECT(hubspot_deal.consorcio_conrado_qualificador_responses, '$.knowledge'), '') AS qualifier_knowledge,
    NULLIF(GET_JSON_OBJECT(hubspot_deal.consorcio_conrado_qualificador_responses, '$.urgency'), '') AS qualifier_urgency,
    simulation_agg.first_simulation_at AS ts_first_simulated,
    simulation_agg.last_simulation_at AS ts_last_simulated,
    COALESCE(simulation_agg.total_simulations, 0) AS total_simulations,
    NUllIF(simulation_agg.first_simulation_credit_value, '') AS first_simulation_amount,
    NUllIF(simulation_agg.last_simulation_credit_value, '') AS last_simulation_amount,
    NUllIF(simulation_agg.avg_simulation_credit_value, '') AS avg_simulation_amount,
    FROM_UTC_TIMESTAMP(hubspot_deal.ts_consorcio_rehabilitation_entered, 'America/Sao_Paulo') AS ts_rehabilitation_entered,
    FROM_UTC_TIMESTAMP(hubspot_deal.ts_consorcio_rehabilitation_exit, 'America/Sao_Paulo') AS ts_rehabilitation_exited,
    FROM_UTC_TIMESTAMP(hubspot_deal.ts_consorcio_template_last_sent, 'America/Sao_Paulo') AS ts_last_template_sent,
    ROW_NUMBER() OVER (
      PARTITION BY hubspot_deal_stage.id_deal
      ORDER BY hubspot_deal_stage.ts_stage_started DESC, CAST(hubspot_deal_stage.id_stage AS BIGINT) DESC
    ) AS rn
  FROM
    datalake_hubspot.deal_stage AS hubspot_deal_stage
  INNER JOIN
    datalake_hubspot.stage AS hubspot_stage
      ON hubspot_stage.id_stage = hubspot_deal_stage.id_stage
  INNER JOIN
    datalake_hubspot.deal AS hubspot_deal
      ON hubspot_deal.id_deal = hubspot_deal_stage.id_deal
  LEFT JOIN
    datalake_consorcio_clean.lead AS consorcio_lead
      ON consorcio_lead.uuid = hubspot_deal.consorcio_id_lead
  LEFT JOIN
    simulation_agg
      ON simulation_agg.id_lead = consorcio_lead.id
  WHERE
    hubspot_deal_stage.id_pipeline = 737631007
),

-- ----------------------------------------------------------------
-- Temporal resolution of the analyst relationship, one row per deal.
-- deal_owner_key is deduped to rn = 1 first, and the interval match
-- is collapsed with ROW_NUMBER so overlapping sheet rows can never
-- fan out and duplicate a deal. Latest start wins on an overlap.
-- ----------------------------------------------------------------
deal_owner_key AS (
  SELECT
    id_deal,
    CAST(id_hubspot_owner AS STRING) AS id_owner,
    DATE(ts_deal_created) AS dt_created
  FROM
    base_all
  WHERE
    rn = 1
),
relationship_matched AS (
  SELECT
    id_deal,
    team,
    supervisor_name,
    analyst_role
  FROM (
    SELECT
      deal_owner_key.id_deal,
      inside_sales_operation.team,
      inside_sales_operation.supervisor_name,
      inside_sales_operation.analyst_role,
      ROW_NUMBER() OVER (
        PARTITION BY deal_owner_key.id_deal
        ORDER BY
          inside_sales_operation.dt_relationship_start DESC,
          inside_sales_operation.dt_relationship_end DESC
      ) AS rn_rel
    FROM
      deal_owner_key
    INNER JOIN
      inside_sales_operation
        ON inside_sales_operation.id_owner = deal_owner_key.id_owner
        AND deal_owner_key.dt_created
              BETWEEN inside_sales_operation.dt_relationship_start
                  AND inside_sales_operation.dt_relationship_end
  ) AS ranked_rel
  WHERE
    rn_rel = 1
),
deal_relationship AS (
  SELECT
    deal_owner_key.id_deal,
    COALESCE(
      relationship_matched.team,
      CASE
        WHEN deal_owner_key.dt_created < analyst_relationship_bounds.dt_first_start
          THEN analyst_first_relationship.team
        WHEN deal_owner_key.dt_created > analyst_relationship_bounds.dt_last_end
          THEN analyst_last_relationship.team
      END
    ) AS team,
    COALESCE(
      relationship_matched.supervisor_name,
      CASE
        WHEN deal_owner_key.dt_created < analyst_relationship_bounds.dt_first_start
          THEN analyst_first_relationship.supervisor_name
        -- analyst already left: team and role carry forward, supervisor does not
        WHEN deal_owner_key.dt_created > analyst_relationship_bounds.dt_last_end
          THEN 'other'
      END
    ) AS supervisor_name,
    COALESCE(
      relationship_matched.analyst_role,
      CASE
        WHEN deal_owner_key.dt_created < analyst_relationship_bounds.dt_first_start
          THEN analyst_first_relationship.analyst_role
        WHEN deal_owner_key.dt_created > analyst_relationship_bounds.dt_last_end
          THEN analyst_last_relationship.analyst_role
      END
    ) AS analyst_role
  FROM
    deal_owner_key
  LEFT JOIN
    relationship_matched
      ON relationship_matched.id_deal = deal_owner_key.id_deal
  LEFT JOIN
    analyst_relationship_bounds
      ON analyst_relationship_bounds.id_owner = deal_owner_key.id_owner
  LEFT JOIN
    analyst_first_relationship
      ON analyst_first_relationship.id_owner = deal_owner_key.id_owner
  LEFT JOIN
    analyst_last_relationship
      ON analyst_last_relationship.id_owner = deal_owner_key.id_owner
)
SELECT
  base_deal.id_deal,
  base_deal.id_hubspot_owner,
  base_deal.id_device,
  base_deal.uuid_lead,
  base_deal.deal_name,
  base_deal.phone_number,
  base_deal.stage_name AS current_stage,
  LOWER(
    CASE
      WHEN base_deal.utm_medium = 'blip_reply' THEN 'repescagem'
      WHEN origin_mapping.origin IS NOT NULL THEN origin_mapping.origin
      WHEN (base_deal.phone_number IS NULL AND (
        base_deal.consorcio_discard_reason IS NULL
        OR base_deal.consorcio_quota_amount IS NULL
      )) THEN 'DAG Fail - Properties Null'
      WHEN base_deal.utm_source IS NOT NULL THEN 'Others'
      ELSE 'Direct'
    END
  ) AS origin,
  base_deal.utm_source,
  LOWER(base_deal.utm_medium) AS utm_medium,
  base_deal.utm_campaign,
  base_deal.utm_content,
  base_deal.utm_term,
  CASE
    WHEN base_deal.utm_source = 'crm' AND base_deal.utm_campaign LIKE '%FR_Tenants%' THEN 'Tenants'
    WHEN base_deal.utm_source = 'crm' AND base_deal.utm_campaign LIKE '%FS_ToF%' THEN 'FS_ToF'
    WHEN base_deal.utm_source = 'crm' AND base_deal.utm_campaign LIKE '%FR_FS_Owners%' THEN 'Owners'
    WHEN base_deal.utm_source = 'crm' AND base_deal.utm_campaign LIKE '%FR_ToF%' THEN 'FR_ToF'
    ELSE segment_mapping.segment
  END AS segment,
  base_deal.consorcio_inside_sales_pipeline AS inside_sales_pipeline,
  base_deal.consorcio_discard_reason AS discard_reason,
  base_deal.consorcio_forms_origin AS forms_origin,
  base_deal.consorcio_lead_priority AS lead_priority,
  base_deal.consorcio_quota_amount AS quota_amount,
  base_deal.consorcio_installment_type AS installment_type,
  base_deal.consorcio_channel_origin AS channel_origin,
  base_deal.amount AS deal_amount,
  base_deal.customer_journey,
  base_deal.qualifier_goal,
  base_deal.qualifier_investment_type,
  base_deal.qualifier_reason,
  base_deal.qualifier_knowledge,
  base_deal.qualifier_urgency,
  base_deal.consorcio_abandoned_cart_template_sent AS abandoned_cart_template_sent,
  CASE
    WHEN LOWER(base_deal.consorcio_abandoned_cart_template_sent) = 'true' THEN 'company_initiated'
    WHEN LOWER(base_deal.consorcio_abandoned_cart_template_sent) = 'false' THEN 'user_initiated'
  END AS contact_type,
  TRY_CAST(base_deal.consorcio_negotiation_value AS DOUBLE) AS negotiation_value,
  base_deal.consorcio_bamaq_proposal_codes AS bamaq_proposal_codes,
  -- ---------------- feedback survey ----------------
  base_deal.feedback_benefits,
  base_deal.feedback_comment,
  base_deal.feedback_score,
  base_deal.is_feedback_contact_allowed,

  base_deal.total_simulations,
  CASE
    WHEN LOWER(base_deal.consorcio_abandoned_cart_template_sent) = 'true' THEN 1
    WHEN LOWER(base_deal.consorcio_abandoned_cart_template_sent) = 'false' THEN 0
  END AS is_abandoned_cart,
  CASE
    WHEN LOWER(CAST(base_deal.consorcio_blip_agent_inactivity AS STRING)) = 'true' THEN 1
    WHEN LOWER(CAST(base_deal.consorcio_blip_agent_inactivity AS STRING)) = 'false' THEN 0
  END AS has_blip_agent_inactivity,
  base_deal.consorcio_template_first_contact AS template_first_contact,
  base_deal.consorcio_template_last_contact AS template_last_contact,
  base_deal.consorcio_group AS group,
  base_deal.consorcio_user_first_message_reply AS user_first_message_reply,
  base_deal.consorcio_entered_rehabilitation AS has_entered_rehabilitation,
  base_deal.consorcio_rehabilitation_exit_reason AS rehabilitation_exit_reason,
  base_deal.consorcio_rehabilitation_variant AS rehabilitation_variant,
  base_deal.consorcio_rehabilitation_trigger_count AS rehabilitation_trigger_count,
  base_deal.consorcio_entered_churn AS has_entered_churn,
  base_deal.consorcio_agent_simulation_value AS agent_simulation_value,
  base_deal.first_simulation_amount,
  base_deal.last_simulation_amount,
  base_deal.avg_simulation_amount,

  -- ---------------- operational: inside-sales attribution ----------------
  COALESCE(analyst_identity.analyst_name, owner_name.analyst_name) AS analyst_name,
  deal_relationship.analyst_role,
  deal_relationship.supervisor_name,
  deal_relationship.team,

  -- ---------------- dates and timestamps ----------------
  DATE(base_deal.ts_deal_created) AS dt_created,
  DATE_TRUNC('month', base_deal.ts_deal_created) AS dt_month_start,
  DATE_TRUNC('week', base_deal.ts_deal_created) AS dt_week_start,
  base_deal.ts_deal_created,
  lead_created.ts_lead_created,
  base_deal.ts_stage_started AS ts_current_stage_started,
  base_deal.ts_first_simulated,
  base_deal.ts_last_simulated,
  base_deal.ts_rehabilitation_entered,
  base_deal.ts_rehabilitation_exited,
  base_deal.ts_last_template_sent,
  YEAR(base_deal.ts_deal_created) AS year,
  MONTH(base_deal.ts_deal_created) AS month,
  DAY(base_deal.ts_deal_created) AS day
FROM
  base_all AS base_deal
LEFT JOIN
  origin_mapping
    ON origin_mapping.utm_source = base_deal.utm_source
LEFT JOIN
  segment_mapping
    ON segment_mapping.utm_campaign = base_deal.utm_campaign
LEFT JOIN
  analyst_identity
    ON analyst_identity.id_owner = CAST(base_deal.id_hubspot_owner AS STRING)
LEFT JOIN
  owner_name
    ON owner_name.id_owner = CAST(base_deal.id_hubspot_owner AS STRING)
LEFT JOIN
  deal_relationship
    ON deal_relationship.id_deal = base_deal.id_deal
LEFT JOIN
  lead_created
    ON lead_created.uuid_lead = base_deal.uuid_lead
WHERE
  DATE(base_deal.ts_deal_created) >= DATE('2025-08-01')
  AND LOWER(base_deal.deal_name) NOT LIKE '%teste%'
  AND LOWER(base_deal.deal_name) NOT LIKE '%testando%'
  AND base_deal.rn = 1
  AND (COALESCE(base_deal.duplication_status, 'unique') = 'unique' OR base_deal.stage_name = 'venda fechada')
