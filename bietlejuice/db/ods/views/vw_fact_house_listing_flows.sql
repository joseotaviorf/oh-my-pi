--drop view if exists vw_fact_house_listing_flows;
--create or replace view vw_fact_house_listing_flows as
WITH potential_listings_enrich AS (
    SELECT
        p.*,
        COALESCE(p.id_city, lcr.id_region, '-1'::INTEGER) AS sk_city,
        us_cad.id IS NOT NULL AS is_call_center,
        us_d.subscriptionSource AS subscription_source,
        COALESCE(p.listing_flows_affiliate_type,
            CASE WHEN ua.affiliateType = 'Doorman' AND u.dados_agente_id IS NOT NULL THEN 'Doorman & Agent'
                 WHEN u.dados_agente_id IS NOT NULL THEN 'Agent'
                 ELSE ua.affiliateType
            END) AS affiliate_type
    FROM potential_listings AS p
    LEFT JOIN usuario AS us_cad
      ON us_cad.id = p.house_usuario_que_cadastrou_id
        AND us_cad.email ~~ '%@hargos.com.br'
    LEFT JOIN usuario AS u
      ON u.id = p.affiliate_id
    LEFT JOIN user_doorman AS us_d
      ON us_d.id_dados_afiliado = u.dados_afiliado_id
    LEFT JOIN user_affiliate AS ua
      ON ua.id = u.dados_afiliado_id
    LEFT JOIN lead_city_region AS lcr
      ON p.region_id = -1 AND p.lead_id = lcr.id_lead
),
taxonomy AS (
  SELECT
    DISTINCT
    lead_type,
    lead_origin,
    lead_tracking_medium,
    lead_tracking_source,
    affiliate_type,
    lead_referring_category,
    is_agent_referral::INTEGER::BOOLEAN AS is_agent_referral,
    is_branded::INTEGER::BOOLEAN AS is_branded,
    is_ops_direct_register::INTEGER::BOOLEAN AS is_ops_direct_register,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source
  FROM
    gsheets.taxonomy_growth
  WHERE
    COALESCE(mkt_medium, '') <> 'Doorman User'
    AND mkt_origin <> 'B2B'
),
applied_taxonomy AS (
SELECT
  pl.*,
  CASE
    WHEN pl.is_branded THEN 'Branded'
    ELSE 'Other'
  END AS mkt_branded,
  CASE
    WHEN pl.is_b2b THEN 'B2B'
    WHEN pl.affiliate_type = 'Doorman' THEN 'Doorman'
    WHEN t.mkt_origin IS NULL THEN 'Other'
    ELSE t.mkt_origin
  END AS mkt_origin,
  CASE
    WHEN pl.is_b2b THEN NULL
    WHEN pl.affiliate_type = 'Doorman' THEN 'Envio'
    WHEN t.mkt_origin IS NULL THEN 'Not Mapped'
    ELSE t.mkt_channel
  END AS mkt_channel,
  CASE
    WHEN t.mkt_origin IS NULL THEN 'Not Mapped'
    WHEN pl.tracking_platform = 'web_mobile' THEN 'Web Mobile'
    WHEN pl.tracking_platform = 'web_desktop' THEN 'Web Desktop'
    ELSE 'Not Mapped'
  END AS mkt_platform,
  CASE
    WHEN pl.is_b2b THEN NULL
    WHEN pl.affiliate_type = 'Doorman' THEN 'Doorman User'
    WHEN t.mkt_origin IS NULL THEN 'Not Mapped'
    ELSE t.mkt_medium
  END AS mkt_medium,
  CASE
    WHEN pl.is_b2b THEN NULL
    WHEN pl.affiliate_type = 'Doorman' THEN (
        CASE
            WHEN COALESCE(pl.subscription_source, '') IN ('', 'Desconhecida')   THEN 'Cadastro Orgânico'
            WHEN pl.subscription_source = 'LeadOutbound'                        THEN 'Captação Call Center'
            WHEN pl.subscription_source = 'Trade'                               THEN 'Captação Offline'
            ELSE t.mkt_source
        END
    )
    WHEN t.mkt_origin IS NULL THEN 'Not Mapped'
    ELSE t.mkt_source
  END AS mkt_source,
  NOW() AS ts_load
FROM potential_listings_enrich AS pl
LEFT JOIN taxonomy AS t
  ON COALESCE(pl.lead_type, '') = COALESCE(t.lead_type, '')
    AND COALESCE(pl.lead_origin, '') = COALESCE(t.lead_origin, '')
    AND COALESCE(pl.utm_source, '') = COALESCE(t.lead_tracking_source, '')
    AND COALESCE(pl.utm_medium, '') = COALESCE(t.lead_tracking_medium, '')
    AND COALESCE(pl.affiliate_type, '') = COALESCE(t.affiliate_type, '')
    AND COALESCE(pl.lead_referring_category, '') = COALESCE(t.lead_referring_category, '')
    AND COALESCE(pl.is_branded, FALSE) = COALESCE(t.is_branded, FALSE)
    AND COALESCE(pl.is_ops_direct_register, false) = COALESCE(t.is_ops_direct_register, FALSE)
    AND COALESCE(pl.is_agent_referral, FALSE) = COALESCE(t.is_agent_referral, FALSE)
),
applied_taxonomy_flow AS (
    SELECT
        *,
        CASE
             WHEN lead_type = 'Proparceria'                                                 THEN 'Non Self-Service'
             WHEN lead_type = 'Marketing' AND lead_origin IN ('Facebook', 'Reprocessado')   THEN 'Non Self-Service'
             WHEN is_ops_direct_register                                                    THEN 'Non Self-Service'
             WHEN lead_origin = 'Landing'                                                   THEN 'Non Self-Service'
             WHEN mkt_origin IN ('Owner PWA', 'Price Calculator')                           THEN 'Self-Service'
             WHEN mkt_origin IN ('Indica Aí - Agents', 'Indica Aí - General')
                  AND mkt_source = 'Direct Referral'                                        THEN 'Self-Service'
             WHEN mkt_origin IN ('Other', 'Not Mapped')                                     THEN mkt_origin
             ELSE 'Non Self-Service'
        END AS mkt_flow
    FROM  applied_taxonomy
)
SELECT
  atax.sk_house_listing_flow,
  atax.sk_condo,
  atax.sk_lead,
  atax.sk_lead_conversion,
  atax.sk_first_photo_job,
  atax.sk_house_listing,
  atax.sk_user_house_registrant,
  atax.sk_user_sales_rep,
  atax.sk_user_lead_affiliate,
  atax.sk_user_first_task_assignee,
  atax.sk_user_last_task_assignee,
  atax.sk_region,
  atax.sk_city,
  atax.sk_partner,
  atax.sk_autonomous_agent,
  atax.sk_lead_date,
  atax.sk_sales_company_lead_sent_date,
  atax.sk_prospect_date,
  atax.sk_first_task_created_date,
  atax.sk_first_task_closed_date,
  atax.sk_last_task_created_date,
  atax.sk_last_task_closed_date,
  atax.sk_first_contact_date,
  atax.sk_conversion_date,
  atax.sk_qualified_date,
  atax.sk_opportunity_date,
  atax.sk_first_listing_date,
  atax.sk_discard_date,
  atax.sk_user_lead_first_discarder,
  atax.sk_user_lead_last_discarder,
  atax.funnel_step,
  atax.funnel_drop_reason,
  atax.hours_lead_to_prospect,
  atax.hours_prospect_to_qualified,
  atax.hours_lead_to_first_contact,
  atax.hours_prospect_to_first_contact,
  atax.hours_qualified_to_opportunity,
  atax.hours_opportunity_to_listing,
  atax.hours_lead_to_listing,
  atax.days_lead_to_prospect,
  atax.days_prospect_to_qualified,
  atax.days_lead_to_first_contact,
  atax.days_prospect_to_first_contact,
  atax.days_qualified_to_opportunity,
  atax.days_opportunity_to_listing,
  atax.days_lead_to_listing,
  atax.days_lead_to_processing,
  atax.is_exclusive,
  atax.first_isales_intervention,
  atax.lead_type,
  atax.lead_origin,
  atax.utm_source AS lead_tracking_source,
  atax.utm_medium AS lead_tracking_medium,
  atax.tracking_platform AS lead_tracking_platform,
  atax.is_branded,
  atax.is_b2b,
  atax.is_autonomous_agent,
  atax.is_doorman,
  atax.is_isales_direct_register,
  atax.is_cx_direct_register,
  atax.is_ops_direct_register,
  atax.has_isales_intervention,
  atax.has_fup_photo_task,
  atax.is_call_center,
  atax.reprocessed_flg AS is_lead_reprocessed,
  atax.affiliate_type,
  atax.is_agent_referral,
  atax.lead_referring_domain,
  atax.lead_referring_category,
  atax.subscription_source,
  atax.mkt_branded,
  CASE WHEN atax.mkt_flow = 'Self-Service' THEN 'Outbound'
       WHEN atax.mkt_flow = 'Non Self-Service' AND atax.lead_origin IN ('App', 'Crawling', 'Form', 'Planilha') THEN 'Outbound'
       WHEN atax.mkt_flow = 'Non Self-Service' AND atax.lead_origin IN ('Facebook', 'Landing', 'OwnerPWA', 'Price Suggestion') THEN 'Inbound'
       WHEN atax.mkt_flow = 'Not Mapped' THEN 'Not Mapped'
       ELSE 'Other' END AS mkt_category,
  atax.mkt_flow,
  CASE WHEN atax.mkt_flow = 'Non Self-Service' THEN 'Non Self-Service'
       WHEN atax.mkt_flow = 'Self-Service' AND not atax.has_isales_intervention THEN 'Full Self-Service'
       WHEN atax.mkt_flow = 'Self-Service' AND atax.has_isales_intervention THEN 'Recovered Self-Service'
       WHEN atax.mkt_flow IN ('Not Mapped', 'Other') THEN atax.mkt_flow
       ELSE 'Not Mapped' END AS mkt_completion,
  atax.mkt_origin,
  atax.mkt_channel,
  atax.mkt_platform,
  atax.mkt_medium,
  atax.mkt_source,
  atax.lead_context_origin,
  atax.listing_sale_status,
  atax.ts_opted_out_rent,
  atax.ts_load
FROM applied_taxonomy_flow AS atax;
