-- ================================================================
-- Consórcio deal entity (current CRM state, deal grain)
-- One row per unique Consórcio deal at its latest HubSpot stage:
-- identity, attribution, ownership, C2W, qualifier, feedback,
-- simulation aggregates, current_stage. Funnel path lives in
-- deal_stage; Funil Cohort is_*/ts_* rollup lives in deal_milestone.
-- Pipeline 737631007. Timestamps in America/Sao_Paulo.
-- Full rebuild each run.
-- ================================================================
WITH origin_mapping AS (
  SELECT
    utm_source,
    origin
  FROM VALUES
    ('newsletter', 'Internal'),
    ('none', 'Direct'),
    ('internal', 'Internal'),
    ('crm', 'CRM'),
    ('insidesales', 'Internal'),
    ('google', 'Google'),
    ('youtube', 'youtube'),
    ('referral', 'Internal'),
    ('fb', 'Meta'),
    ('ig', 'Meta'),
    -- HubSpot token is {{site_source_name}} in data; double braces in REPEAT survive str.format.
    (CONCAT(REPEAT('{{', 2), 'site_source_name', REPEAT('}}', 2)), 'Meta'),
    ('(none)', 'Direct'),
    ('instagram', 'Meta'),
    ('imovelweb', 'Imovelweb'),
    ('buzzlead', 'Others'),
    ('(Nenhum valor)', 'Direct'),
    ('TikTok', 'Others'),
    ('qa_consorcio_lp', 'C2W'),
    ('display', 'Meta'),
    ('repescagem', 'repescagem'),
    ('sfmc', 'crm')
    AS origin_map(utm_source, origin)
),
segment_mapping AS (
  SELECT
    utm_campaign,
    segment
  FROM VALUES
    ('consorcio_launch___ED_Institucional_EX', 'Branded'),
    ('sitelinks_branded_consorcio', 'Branded'),
    ('comunicacao__lançamento', 'Branded'),
    ('consorcio_launch___ED_Institucional_FR', 'Branded'),
    ('RJ_BRANDED', 'Branded'),
    ('SP_BRANDED', 'Branded'),
    ('FLN_BRANDED', 'Branded'),
    ('POA_branded', 'Branded'),
    ('consorcio_launch___ED_Concorrentes_AM', 'Non-Branded'),
    ('consorcio_launch___ED_Consorcio_de_Casa_AM', 'Non-Branded'),
    ('consorcio_launch___ED_Carta_de_Credito_AM', 'Non-Branded'),
    ('consorcio_launch___ED_Consorcio_de_Imoveis_AM', 'Non-Branded'),
    ('consorcio_launch___ED_Consorcio_Imobiliario_AM', 'Non-Branded'),
    ('consorcio_launch___ED_Investimento_AM', 'Non-Branded'),
    ('consorcio_launch___ED_Planejamento_Financeiro_AM', 'Non-Branded'),
    ('consorcio_launch___ED_Taxa_de_Administracao_AM', 'Non-Branded'),
    ('[ED] Institucional_EX', 'Search Branded'),
    ('[ED] Institucional_FR', 'Search Branded'),
    ('[ED] Concorrentes_AM', 'Search Non Branded'),
    ('[ED] Carta de Crédito_AM', 'Search Non Branded'),
    ('[ED] Consórcio Imobiliário_AM', 'Search Non Branded'),
    ('[ED] Consórcio de Casa_AM', 'Search Non Branded'),
    ('[ED] Investimento_AM', 'Search Non Branded'),
    ('[ED] Consórcio de Imóveis_AM', 'Search Non Branded'),
    ('[ED] Planejamento Financeiro_AM', 'Search Non Branded'),
    ('[ED] Taxa de Administração_AM', 'Search Non Branded'),
    ('[ED] Consórcio+Valor_AM', 'Search Non Branded'),
    ('[ED] Concorrentes_EX', 'Search Non Branded'),
    ('[ED] PMáx - Consórcio', 'Google PMAX'),
    ('consorcio_launch___ED_PMáx_Consórcio', 'Google PMAX'),
    ('[ED] YouTube - Demand Gen - SP + PortoAlegre', 'YouTube'),
    ('[ED] display_aquisição_consorcio', 'Meta Ads'),
    ('[ED]ASC/amplo_consorcio_launch', 'Meta Ads'),
    ('[ED] display_remarketing_consorcio', 'Meta Ads')
    AS segment_map(utm_campaign, segment)
),
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
analyst_ops AS (
  SELECT
    id_owner,
    role,
    supervisor
  FROM VALUES
    ('83834497', 'Senior', 'Beatriz'),
    ('84909664', 'Pleno', 'Erick'),
    ('81197710', 'Junior', 'Bianca'),
    ('83834581', 'Senior', 'n/a'),
    ('84909665', 'Pleno', 'n/a'),
    ('84864479', 'Pleno', 'Bianca'),
    ('84050436', 'Senior', 'Erick'),
    ('84050487', 'Pleno', 'Erick'),
    ('83263494', 'Pleno', 'n/a'),
    ('82473891', 'Senior', 'Erick'),
    ('86362795', 'Pleno', 'Beatriz'),
    ('85434798', 'Senior', 'Bianca'),
    ('83834547', 'Senior', 'Erick'),
    ('85655480', 'Pleno', 'Erick'),
    ('83263457', 'Pleno', 'Beatriz'),
    ('83777915', 'Senior', 'n/a'),
    ('85321623', 'Pleno', 'Bianca'),
    ('84050586', 'Pleno', 'Erick'),
    ('81552418', 'Senior', 'Beatriz'),
    ('85180360', 'Pleno', 'n/a'),
    ('85180405', 'Senior', 'Bianca'),
    ('84050544', 'Senior', 'Erick'),
    ('85434858', 'Pleno', 'Beatriz'),
    ('80570949', 'Senior', 'n/a'),
    ('85325992', 'Pleno', 'Bianca'),
    ('85321594', 'Pleno', 'Beatriz'),
    ('82032559', 'Pleno', 'n/a'),
    ('83263567', 'Pleno', 'Beatriz'),
    ('82467411', 'Senior', 'Beatriz'),
    ('90624808', 'Senior', 'Erick'),
    ('90628391', 'Pleno', 'Bianca'),
    ('90728482', 'Pleno', 'Erick'),
    ('81556428', 'Senior', 'Bianca'),
    ('84306295', 'Senior', 'Bamaq'),
    ('85173258', 'Senior', 'Bamaq'),
    ('84306345', 'Senior', 'Bamaq'),
    ('92712595', 'Pleno', 'Bianca'),
    ('93485724', 'Pleno', 'Beatriz')
    AS analyst_map(id_owner, role, supervisor)
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
    COUNT(*) AS total_simulations
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
)
SELECT
  base_deal.id_deal,
  base_deal.id_hubspot_owner,
  base_deal.id_device,
  base_deal.uuid_lead,
  base_deal.deal_name,
  base_deal.stage_name AS current_stage,
  LOWER(
    CASE
      WHEN base_deal.utm_medium = 'blip_reply' THEN 'repescagem'
      WHEN origin_mapping.origin IS NOT NULL THEN origin_mapping.origin
      WHEN (
        base_deal.consorcio_discard_reason IS NULL
        OR base_deal.consorcio_quota_amount IS NULL
      ) THEN 'DAG Fail - Properties Null'
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
  base_deal.feedback_benefits,
  base_deal.feedback_comment,
  owner_name.analyst_name,
  analyst_ops.role AS analyst_role,
  analyst_ops.supervisor AS supervisor_name,
  base_deal.feedback_score,
  base_deal.total_simulations,
  CASE
    WHEN LOWER(base_deal.consorcio_abandoned_cart_template_sent) = 'true' THEN 1
    WHEN LOWER(base_deal.consorcio_abandoned_cart_template_sent) = 'false' THEN 0
  END AS is_abandoned_cart,
  CASE
    WHEN LOWER(CAST(base_deal.consorcio_blip_agent_inactivity AS STRING)) = 'true' THEN 1
    WHEN LOWER(CAST(base_deal.consorcio_blip_agent_inactivity AS STRING)) = 'false' THEN 0
  END AS has_blip_agent_inactivity,
  base_deal.is_feedback_contact_allowed,
  DATE(base_deal.ts_deal_created) AS dt_created,
  DATE_TRUNC('month', base_deal.ts_deal_created) AS dt_month_start,
  DATE_TRUNC('week', base_deal.ts_deal_created) AS dt_week_start,
  base_deal.ts_deal_created,
  lead_created.ts_lead_created,
  base_deal.ts_stage_started AS ts_current_stage_started,
  base_deal.ts_first_simulated,
  base_deal.ts_last_simulated,
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
  owner_name
    ON owner_name.id_owner = CAST(base_deal.id_hubspot_owner AS STRING)
LEFT JOIN
  analyst_ops
    ON analyst_ops.id_owner = CAST(base_deal.id_hubspot_owner AS STRING)
LEFT JOIN
  lead_created
    ON lead_created.uuid_lead = base_deal.uuid_lead
WHERE
  DATE(base_deal.ts_deal_created) >= DATE('2025-08-01')
  AND base_deal.deal_name NOT LIKE '%Teste%'
  AND base_deal.deal_name NOT LIKE '%test%'
  AND base_deal.rn = 1
  AND COALESCE(base_deal.duplication_status, 'unique') = 'unique'
