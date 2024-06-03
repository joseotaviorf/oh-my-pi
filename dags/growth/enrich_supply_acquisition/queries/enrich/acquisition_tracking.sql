WITH 1p_union AS
(
  -- 1P
    SELECT
        sk_supply_lead,
        business_context,
        id_lead,
        id_lead_ebdb,
        id_region,
        id_referred_by,
        CAST(NULL AS INTEGER) AS id_wololo,
        CAST(NULL AS INTEGER) AS id_house,
        business_event,
        funnel_step,
        supply_source,
        aux_product_status,
        CAST(NULL AS STRING) AS drop_step_reason,
        CAST(NULL AS STRING) AS ops_assigned,
        funnel_level,
        ts_event,
        ts_load
    FROM datalake_supply_flows.leads_1p
    UNION
    SELECT
        sk_supply_lead,
        business_context,
        id_lead,
        id_lead_ebdb,
        id_region,
        id_referred_by,
        id_wololo,
        id_house,
        business_event,
        funnel_step,
        supply_source,
        aux_product_status,
        drop_step_reason,
        ops_assigned,
        funnel_level,
        ts_event,
        ts_load
    FROM datalake_supply_flows.prospects_1p  
),
3p_union AS (
    -- 3p
    SELECT  
        sk_supply_lead,
        business_context,
        id_lead,
        id_lead_ebdb,
        id_region,
        -1 AS id_referred_by,
        business_event,
        funnel_step,
        supply_source,
        aux_product_status,
        CAST(NULL AS STRING) AS drop_step_reason,
        CAST(NULL AS STRING) AS ops_assigned,
        funnel_level,
        ts_event,
        ts_load
    FROM datalake_supply_flows.leads_3p
    UNION
    SELECT 
        sk_supply_lead,
        business_context,
        id_lead,
        id_lead_ebdb,
        id_region,
        -1 AS id_referred_by,
        business_event,
        funnel_step,
        supply_source,
        aux_product_status,
        drop_step_reason,
        CAST(NULL AS STRING) AS ops_assigned,
        funnel_level,
        ts_event,
        ts_load
    FROM datalake_supply_flows.prospects_3p
),

ciq_union AS (
-- CIQ
    SELECT 
        sk_supply_lead,
        business_context,
        id_lead,
        id_lead_ebdb,
        id_region,
        id_user_registrant AS id_referred_by,
        business_event,
        funnel_step,
        supply_source,
        aux_product_status,
        CAST(NULL AS STRING) AS drop_step_reason,
        CAST(NULL AS STRING) AS ops_assigned,
        funnel_level,
        ts_event,
        ts_load
    FROM datalake_supply_flows.leads_ciq
    UNION 
    SELECT 
        sk_supply_lead,
        business_context,
        id_lead,
        id_lead_ebdb,
        id_region,
        id_user_registrant AS id_referred_by,
        business_event,
        funnel_step,
        supply_source,
        aux_product_status,
        CAST(NULL AS STRING) AS drop_step_reason,
        CAST(NULL AS STRING) AS ops_assigned,
        funnel_level,
        ts_event,
        ts_load
    FROM datalake_supply_flows.prospects_ciq
),
event_tracking_1p AS (
    SELECT
        et.sk_supply_lead,
        et.business_context,
        et.id_lead,
        et.id_lead_ebdb,
        et.id_region,
        et.id_referred_by,
        et.id_wololo,
        et.id_house,
        et.business_event,
        et.funnel_step,
        et.supply_source,
        et.drop_step_reason,
        et.funnel_level,
        et.aux_product_status,
        et.ts_event,
        et.ts_load,
        lo.affiliate_type,
        COALESCE(lo.campaign, -1) AS campaign,
        COALESCE(lo.medium, -1) AS medium,
        COALESCE(lo.source, -1) AS source,
        lo.ops_agent,
        lo.ops_objective,
        lo.ops_partner,
        et.ops_assigned,
        lo.application,
        lo.landing_page,
        lo.reprocessed,
        lo.ops_approach,
        lo.ops_contact_medium,
        lo.platform,
        lo.lead_type,
        lo.original_lead,
        lo.database_tracking_campaign,
        lo.database_tracking_medium,
        lo.database_tracking_source
    FROM 1p_union AS et
    LEFT JOIN datalake_supply_flows.lead_origin AS lo 
        USING(id_lead)
),
event_tracking_3p AS (
    SELECT 
    et.sk_supply_lead,
    et.business_context,
    et.id_lead,
    et.id_lead_ebdb,
    et.id_region,
    et.id_referred_by,
    CAST(NULL AS BIGINT) AS id_wololo,
    CAST(NULL AS BIGINT) AS id_house,
    et.business_event,
    et.funnel_step,
    et.supply_source,
    et.drop_step_reason,
    et.funnel_level,
    et.aux_product_status,
    et.ts_event,
    et.ts_load,
    CAST(NULL AS STRING) AS affiliate_type,
    CAST(-1 AS STRING) AS campaign,
    CAST(-1 AS STRING) AS medium,
    CAST(-1 AS STRING) AS source,
    CAST(NULL AS STRING) AS ops_agent,
    CAST(NULL AS STRING) AS ops_objective,
    CAST(NULL AS STRING) AS ops_partner,
    CAST(NULL AS STRING) AS ops_assigned,
    'supplyprocessor' AS application,
    CAST(NULL AS STRING) AS landing_page,
    CAST(NULL AS STRING) AS reprocessed,
    CAST(NULL AS STRING) AS ops_approach,
    CAST(NULL AS STRING) AS ops_contact_medium,
    CAST(NULL AS STRING) AS platform,
    CAST(NULL AS STRING) AS lead_type,
    -1 AS original_lead,
    CAST('3p_supply_processor' AS STRING) AS database_tracking_campaign,
    CAST('3p_supply_processor' AS STRING) AS database_tracking_medium,
    CAST('3p_supply_processor' AS STRING) AS database_tracking_source
    FROM 3p_union AS et
),
event_tracking_ciq AS (
    SELECT 
        et.sk_supply_lead,
        et.business_context,
        et.id_lead,
        et.id_lead_ebdb,
        et.id_region,
        et.id_referred_by,
        CAST(NULL AS BIGINT) AS id_wololo,
        CAST(NULL AS BIGINT) AS id_house,
        et.business_event,
        et.funnel_step,
        et.supply_source,
        et.drop_step_reason,
        et.funnel_level,
        et.aux_product_status,
        et.ts_event,
        et.ts_load,
        CAST(NULL AS STRING) AS affiliate_type,
        CAST(-1 AS STRING) AS campaign,
        CAST(-1 AS STRING) AS medium,
        CAST(-1 AS STRING) AS source,
        CAST(NULL AS STRING) AS ops_agent,
        CAST(NULL AS STRING) AS ops_objective,
        CAST(NULL AS STRING) AS ops_partner,
        CAST(NULL AS STRING) AS ops_assigned,
        'consultantpwa' AS application,
        CAST(NULL AS STRING) AS landing_page,
        CAST(NULL AS STRING) AS reprocessed,
        CAST(NULL AS STRING) AS ops_approach,
        CAST(NULL AS STRING) AS ops_contact_medium,
        CAST(NULL AS STRING) AS platform,
        CAST(NULL AS STRING) AS lead_type,
        -1 AS original_lead,
        CAST('ciq_bob' AS STRING) AS database_tracking_campaign,
        CAST('ciq_bob' AS STRING) AS database_tracking_medium,
        CAST('ciq_bob' AS STRING) AS database_tracking_source
    FROM ciq_union AS et
),

all_tracking AS (
  SELECT *
  FROM event_tracking_1p
  UNION ALL
  SELECT *
  FROM event_tracking_3p
  UNION ALL
  SELECT *
  FROM event_tracking_ciq
)

SELECT
  sk_supply_lead,
  business_context,
  id_lead,
  id_lead_ebdb,
  id_region,
  id_referred_by,
  id_wololo,
  id_house,
  business_event,
  funnel_step,
  supply_source,
  drop_step_reason,
  funnel_level,
  aux_product_status,
  affiliate_type,
  campaign,
  medium,
  source,
  ops_agent,
  ops_objective,
  ops_partner,
  ops_assigned,
  application,
  landing_page,
  reprocessed,
  ops_approach,
  ops_contact_medium,
  platform,
  lead_type,
  original_lead,
  database_tracking_campaign,
  database_tracking_medium,
  database_tracking_source,
  ts_event,
  ts_load
FROM
  all_tracking
UNION ALL
-- Adding backfill cases
SELECT
  sk_supply_lead,
  business_context,
  id_lead,
  id_lead_ebdb,
  id_region,
  id_referred_by,
  id_wololo,
  id_house,
  business_event,
  funnel_step,
  supply_source,
  drop_step_reason,
  funnel_level,
  aux_product_status,
  affiliate_type,
  COALESCE(campaign, -1) AS campaign,
  COALESCE(medium, -1) AS medium,
  COALESCE(source, -1) AS source,
  ops_agent,
  ops_objective,
  ops_partner,
  ops_assigned,
  application,
  landing_page,
  reprocessed,
  ops_approach,
  ops_contact_medium,
  platform,
  lead_type,
  original_lead,
  database_tracking_campaign,
  database_tracking_medium,
  database_tracking_source,
  ts_event,
  ts_load
FROM
  datalake_supply_flows.acquisition_backfill AS ab
LEFT ANTI JOIN all_tracking AS at
  ON (ab.id_lead_ebdb = at.id_lead_ebdb)
    AND (ab.supply_source = at.supply_source)