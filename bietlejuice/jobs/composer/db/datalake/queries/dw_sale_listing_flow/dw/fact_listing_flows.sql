WITH potential_listings AS (
    SELECT
        COALESCE(lfrl.id, -1) AS sk_house_listing_flow,
        COALESCE(lfrl.id_lead, -1) AS sk_lead,
        COALESCE(lfrl.id_conversion, -1) AS sk_lead_conversion,
        COALESCE(lfrl.id_photo_job, -1) AS sk_first_photo_job,
        COALESCE(plb2b.id_house_listing, -1) AS sk_house_listing,
        COALESCE(plb2b.id_condo, -1) AS sk_condo,
        COALESCE(lfrl.id_rep, -1) AS sk_user_house_registrant,
        COALESCE(lfrl.id_affiliate, lfrl.id_user_has_indicated, -1) AS sk_user_lead_affiliate,
        COALESCE(lfrl.id_region, -1) AS sk_region,
        COALESCE(pllt.id_user_sales_rep, -1) AS sk_user_sales_rep,
        COALESCE(pllt.id_user_first_task_assignee, -1) AS sk_user_first_task_assignee,
        COALESCE(pllt.id_user_last_task_assignee, -1) AS sk_user_last_task_assignee,
        COALESCE(plb2b.id_partner, -1) AS sk_partner,
        COALESCE(plb2b.id_autonomous_agent, -1) AS sk_autonomous_agent,
        COALESCE(CAST(DATE_FORMAT(pllt.dt_first_task_created_date, "yyyyMMdd") AS BIGINT), -1) AS sk_first_task_created_date,
        COALESCE(CAST(DATE_FORMAT(pllt.dt_first_task_closed_date, "yyyyMMdd") AS BIGINT), -1) AS sk_first_task_closed_date,
        COALESCE(CAST(DATE_FORMAT(pllt.dt_last_task_created_date, "yyyyMMdd") AS BIGINT), -1) AS sk_last_task_created_date,
        COALESCE(CAST(DATE_FORMAT(pllt.dt_last_task_closed_date, "yyyyMMdd") AS BIGINT), -1) AS sk_last_task_closed_date,
        COALESCE(CAST(DATE_FORMAT(lfrl.ts_lead, "yyyyMMdd") AS BIGINT), -1) AS sk_lead_date,
        COALESCE(CAST(DATE_FORMAT(lfrl.ts_prospect, "yyyyMMdd") AS BIGINT), -1) AS sk_prospect_date,
        COALESCE(CAST(DATE_FORMAT(lfrl.ts_first_contact, "yyyyMMdd") AS BIGINT), -1) AS sk_first_contact_date,
        COALESCE(CAST(DATE_FORMAT(lfrl.ts_conversion, "yyyyMMdd") AS BIGINT), -1) AS sk_conversion_date,
        COALESCE(CAST(DATE_FORMAT(lfrl.ts_qualified, "yyyyMMdd") AS BIGINT), -1) AS sk_qualified_date,
        COALESCE(CAST(DATE_FORMAT(lfrl.ts_opportunity, "yyyyMMdd") AS BIGINT), -1) AS sk_opportunity_date,
        COALESCE(CAST(DATE_FORMAT(lfrl.ts_first_listing, "yyyyMMdd") AS BIGINT), -1) AS sk_first_listing_date,
        COALESCE(CAST(DATE_FORMAT(lfrl.ts_discarded, "yyyyMMdd") AS BIGINT), -1) AS sk_discard_date,
        COALESCE(CAST(DATE_FORMAT(lfrl.ts_sales_company_sent, "yyyyMMdd") AS BIGINT), -1) AS sk_sales_company_lead_sent_date,
        COALESCE(lfrl.id_user_lead_first_discarder, -1) AS sk_user_lead_first_discarder,
        COALESCE(lfrl.id_user_lead_last_discarder, -1) AS sk_user_lead_last_discarder,
        COALESCE(lfrl.id_affiliate, lfrl.id_user_has_indicated, -1) AS id_affiliate,
        lfrl.id_lead,
        COALESCE(lfrl.id_region, -1) AS id_region,
        COALESCE(dr.city_id, -1) AS id_city,
        plb2b.id_user_registrant,
        plb2b.is_exclusive,
        COALESCE(
            LOWER(TRIM(lfet.tracking_campaign)) RLIKE '(institucional)|(branded)'
                AND LOWER(TRIM(lfet.tracking_campaign)) NOT RLIKE '(non-branded)',
            plrl.is_lead_branded
        ) AS is_branded,
        (plrl.is_b2b OR lfrl.is_b2b) AS is_b2b, -- Using business rules for both constraints of old b2b and new one
        plb2b.is_autonomous_agent,
        plrl.is_reprocessed,
        lfrl.acquisition_channel_rep = 'Inside Sales' AS is_isales_direct_register,
        lfrl.acquisition_channel_rep = 'Admin' AS is_cx_direct_register,
        (lfrl.acquisition_channel_rep = 'Inside Sales') OR (lfrl.acquisition_channel_rep = 'Admin') AS is_ops_direct_register,
        lfrl.is_agent_referral,
        lfrl.is_doorman,
        pllt.has_isales_intervention,
        pllt.has_fup_photo_task,
        lfrl.flow,
        lfrl.acquisition_method,
        lfrl.acquisition_channel,
        lfrl.acquisition_source,
        CASE
          WHEN lfrl.ts_first_listing IS NOT NULL THEN 'listing'
          WHEN lfrl.ts_opportunity IS NOT NULL THEN 'opportunity'
          WHEN lfrl.ts_qualified IS NOT NULL THEN 'qualified'
          WHEN lfrl.ts_first_contact IS NOT NULL THEN 'first contact'
          WHEN lfrl.ts_prospect IS NOT NULL THEN 'prospect'
          WHEN lfrl.ts_lead IS NOT NULL THEN 'lead'
          ELSE NULL
        END AS funnel_step,
        lfrl.funnel_step AS funnel_drop_reason,
        pllt.first_isales_intervention,
        plrl.lead_type,
        plrl.lead_origin,
        CASE
            WHEN lfet.id_lead IS NOT NULL
                THEN lfet.tracking_source
            ELSE plrl.utm_source
        END AS utm_source,
        CASE
            WHEN lfet.id_lead IS NOT NULL
                THEN lfet.tracking_medium
            ELSE plrl.utm_medium
        END AS utm_medium,
        lfet.tracking_platform,
        lfet.tracking_referring_domain AS lead_referring_domain,
        CASE
          WHEN LOWER(lfet.tracking_referring_domain) LIKE '%corretor%' THEN 'Agents'
          WHEN LOWER(lfet.tracking_referring_domain) LIKE '%indicaai%' THEN 'Indica Ai'
          WHEN LOWER(lfet.tracking_referring_domain) LIKE '%proprietario%' THEN 'Owner'
          ELSE 'Other'
        END AS lead_referring_category,
        lfrl.affiliate_type AS listing_flows_affiliate_type,
        lfrl.lead_context_origin,
        lfrl.listing_rent_status,
        lfrl.hours_lead_to_prospect,
        lfrl.hours_prospect_to_qualified,
        lfrl.hours_lead_to_first_contact,
        lfrl.hours_prospect_to_first_contact,
        lfrl.hours_qualified_to_opportunity,
        lfrl.hours_opportunity_to_listing,
        lfrl.hours_lead_to_listing,
        lfrl.days_lead_to_prospect,
        lfrl.days_prospect_to_qualified,
        lfrl.days_lead_to_first_contact,
        lfrl.days_prospect_to_first_contact,
        lfrl.days_qualified_to_opportunity,
        lfrl.days_opportunity_to_listing,
        lfrl.days_lead_to_listing,
        lfrl.days_lead_to_processing,
        lfrl.ts_opt_out_sale
      FROM datalake_listing_flow.sales_listing_flows_with_reprocessed_leads lfrl
      LEFT JOIN datalake_lead_tracking.lead_first_event_tracking lfet
        ON lfet.id_lead = lfrl.id_lead
      LEFT JOIN datalake_sale_potential_listing.potential_listing_lead_tasks pllt
        ON pllt.id = lfrl.id
      LEFT JOIN datalake_sale_potential_listing.potential_listing_reprocessed_leads plrl
        ON plrl.id = lfrl.id
      LEFT JOIN dw_janus.dim_region dr
        ON dr.sk_region = lfrl.id_region
      LEFT JOIN datalake_sale_potential_listing.potential_listing_b2b plb2b
        ON plb2b.id = lfrl.id
),
potential_listings_enrich AS (
    SELECT
        p.*,
        COALESCE(p.id_city, lcr.id_region, -1) AS sk_city,
        us_cad.id IS NOT NULL AS is_call_center,
        us_d.subscription_source,
        COALESCE(p.listing_flows_affiliate_type,
            CASE
                WHEN ad.affiliate_type = 'Doorman' AND u.id_agent IS NOT NULL
                    THEN 'Doorman & Agent'
                WHEN u.id_agent IS NOT NULL
                    THEN 'Agent'
                ELSE ad.affiliate_type
            END) AS affiliate_type
    FROM potential_listings AS p
    LEFT JOIN datalake_ebdb_clean.user AS us_cad
        ON us_cad.id = p.id_user_registrant
        AND us_cad.email LIKE '%@hargos.com.br'
    LEFT JOIN datalake_ebdb_clean.user AS u
      ON u.id = p.id_affiliate
    LEFT JOIN datalake_ebdb_user.user_doorman AS us_d
      ON us_d.id_affiliate_data = u.id_affiliates
    LEFT JOIN datalake_ebdb_clean.affiliate_data AS ad
      ON ad.id = u.id_affiliates
    LEFT JOIN datalake_lead.lead_city_region AS lcr
      ON lcr.id_lead = p.id_lead AND p.id_region = -1
),
taxonomy AS (
    SELECT DISTINCT
        lead_type,
        lead_origin,
        lead_tracking_medium,
        lead_tracking_source,
        affiliate_type,
        lead_referring_category,
        CAST(is_agent_referral AS BOOLEAN) AS is_agent_referral,
        CAST(is_branded AS BOOLEAN) AS is_branded,
        CAST(is_ops_direct_register AS BOOLEAN) AS is_ops_direct_register,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source
    FROM
        datalake_gsheets_clean.taxonomy_growth
    WHERE COALESCE(mkt_medium, '') <> 'Doorman User'
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
            WHEN pl.is_autonomous_agent AND t.mkt_origin = 'Backend' THEN 'CIQ' --In a few cases, the flag may change and consequently the result will retroactively change back to backend
            WHEN pl.affiliate_type = 'Doorman' THEN 'Doorman'
            WHEN t.mkt_origin IS NULL THEN 'Other'
            ELSE t.mkt_origin
        END AS mkt_origin,
        CASE
            WHEN pl.is_b2b THEN NULL
            WHEN pl.is_autonomous_agent AND t.mkt_origin = 'Backend' THEN NULL
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
            WHEN pl.is_autonomous_agent AND t.mkt_origin = 'Backend' THEN NULL
            WHEN pl.affiliate_type = 'Doorman' THEN 'Doorman User'
            WHEN t.mkt_origin IS NULL THEN 'Not Mapped'
            ELSE t.mkt_medium
        END AS mkt_medium,
        CASE
            WHEN pl.is_b2b THEN NULL
            WHEN pl.is_autonomous_agent AND t.mkt_origin = 'Backend' THEN NULL
            WHEN pl.affiliate_type = 'Doorman' THEN (
                CASE
                    WHEN COALESCE(pl.subscription_source, '') IN ('', 'Desconhecida') THEN 'Cadastro Orgânico'
                    WHEN pl.subscription_source = 'LeadOutbound' THEN 'Captação Call Center'
                    WHEN pl.subscription_source = 'Trade' THEN 'Captação Offline'
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
             WHEN lead_type = 'Proparceria' THEN 'Non Self-Service'
             WHEN lead_type = 'Marketing' AND lead_origin IN ('Facebook', 'Reprocessado') THEN 'Non Self-Service'
             WHEN is_ops_direct_register THEN 'Non Self-Service'
             WHEN lead_origin = 'Landing' THEN 'Non Self-Service'
             WHEN mkt_origin IN ('Owner PWA', 'Price Calculator') THEN 'Self-Service'
             WHEN mkt_origin IN ('Indica Aí - Agents', 'Indica Aí - General')
                  AND mkt_source = 'Direct Referral' THEN 'Self-Service'
             WHEN mkt_origin IN ('Other', 'Not Mapped') THEN mkt_origin
             ELSE 'Non Self-Service'
        END AS mkt_flow
    FROM  applied_taxonomy
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  CAST(atax.sk_house_listing_flow AS BIGINT) AS sk_house_listing_flow,
  CAST(atax.sk_condo AS BIGINT) AS sk_condo,
  CAST(atax.sk_lead AS INTEGER) AS sk_lead,
  CAST(atax.sk_lead_conversion AS INTEGER) AS sk_lead_conversion,
  CAST(atax.sk_first_photo_job AS INTEGER) AS sk_first_photo_job,
  CAST(atax.sk_house_listing AS BIGINT) AS sk_house_listing,
  CAST(atax.sk_user_house_registrant AS INTEGER) AS sk_user_house_registrant,
  CAST(atax.sk_user_sales_rep AS INTEGER) AS sk_user_sales_rep,
  CAST(atax.sk_user_lead_affiliate AS INTEGER) AS sk_user_lead_affiliate,
  CAST(atax.sk_user_first_task_assignee AS INTEGER) AS sk_user_first_task_assignee,
  CAST(atax.sk_user_last_task_assignee AS INTEGER) AS sk_user_last_task_assignee,
  CAST(atax.sk_region AS INTEGER) AS sk_region,
  CAST(atax.sk_city AS INTEGER) AS sk_city,
  CAST(atax.sk_partner AS INTEGER) AS sk_partner,
  CAST(atax.sk_lead_date AS INTEGER) AS sk_lead_date,
  CAST(atax.sk_sales_company_lead_sent_date AS INTEGER) AS sk_sales_company_lead_sent_date,
  CAST(atax.sk_prospect_date AS INTEGER) AS sk_prospect_date,
  CAST(atax.sk_first_task_created_date AS INTEGER) AS sk_first_task_created_date,
  CAST(atax.sk_first_task_closed_date AS INTEGER) AS sk_first_task_closed_date,
  CAST(atax.sk_last_task_created_date AS INTEGER) AS sk_last_task_created_date,
  CAST(atax.sk_last_task_closed_date AS INTEGER) AS sk_last_task_closed_date,
  CAST(atax.sk_first_contact_date AS INTEGER) AS sk_first_contact_date,
  CAST(atax.sk_conversion_date AS INTEGER) AS sk_conversion_date,
  CAST(atax.sk_qualified_date AS INTEGER) AS sk_qualified_date,
  CAST(atax.sk_opportunity_date AS INTEGER) AS sk_opportunity_date,
  CAST(atax.sk_first_listing_date AS INTEGER) AS sk_first_listing_date,
  CAST(atax.sk_discard_date AS INTEGER) AS sk_discard_date,
  CAST(atax.sk_user_lead_first_discarder AS INTEGER) AS sk_user_lead_first_discarder,
  CAST(atax.sk_user_lead_last_discarder AS INTEGER) AS sk_user_lead_last_discarder,
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
  CAST(atax.is_exclusive AS SMALLINT) AS is_exclusive,
  atax.first_isales_intervention,
  NULLIF(atax.lead_type, '') AS lead_type,
  NULLIF(atax.lead_origin, '') AS lead_origin,
  NULLIF(atax.utm_source, '') AS lead_tracking_source,
  NULLIF(atax.utm_medium, '') AS lead_tracking_medium,
  NULLIF(atax.tracking_platform, '') AS lead_tracking_platform,
  atax.is_branded,
  atax.is_b2b,
  atax.is_doorman,
  atax.is_isales_direct_register,
  atax.is_cx_direct_register,
  atax.is_ops_direct_register,
  atax.has_isales_intervention,
  atax.has_fup_photo_task,
  atax.is_call_center,
  atax.is_reprocessed AS is_lead_reprocessed,
  atax.affiliate_type,
  atax.is_agent_referral,
  NULLIF(atax.lead_referring_domain, '') AS lead_referring_domain,
  NULLIF(atax.lead_referring_category, '') AS lead_referring_category,
  atax.subscription_source,
  NULLIF(atax.mkt_branded, '') AS mkt_branded,
  CASE WHEN atax.mkt_flow = 'Self-Service' THEN 'Outbound'
       WHEN atax.mkt_flow = 'Non Self-Service' AND atax.lead_origin IN ('App', 'Crawling', 'Form', 'Planilha') THEN 'Outbound'
       WHEN atax.mkt_flow = 'Non Self-Service' AND atax.lead_origin IN ('Facebook', 'Landing', 'OwnerPWA', 'Price Suggestion') THEN 'Inbound'
       WHEN atax.mkt_flow = 'Not Mapped' THEN 'Not Mapped'
       ELSE 'Other' END AS mkt_category,
  NULLIF(atax.mkt_flow, '') AS mkt_flow,
  CASE WHEN atax.mkt_flow = 'Non Self-Service' THEN 'Non Self-Service'
       WHEN atax.mkt_flow = 'Self-Service' AND not atax.has_isales_intervention THEN 'Full Self-Service'
       WHEN atax.mkt_flow = 'Self-Service' AND atax.has_isales_intervention THEN 'Recovered Self-Service'
       WHEN atax.mkt_flow IN ('Not Mapped', 'Other') THEN NULLIF(atax.mkt_flow, '')
       ELSE 'Not Mapped' END AS mkt_completion,
  NULLIF(atax.mkt_origin, '') AS mkt_origin,
  NULLIF(atax.mkt_channel, '') AS mkt_channel,
  NULLIF(atax.mkt_platform, '') AS mkt_platform,
  NULLIF(atax.mkt_medium, '') AS mkt_medium,
  NULLIF(atax.mkt_source, '') AS mkt_source,
  atax.lead_context_origin,
  atax.listing_rent_status,
  CAST(atax.ts_opt_out_sale AS TIMESTAMP) AS ts_opt_out_sale,
  atax.ts_load
FROM applied_taxonomy_flow AS atax