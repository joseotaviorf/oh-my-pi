WITH max_date_obt AS (
    SELECT 
        MAX(date) AS max_date 
    FROM 
        dw_growth.obt_supply
),
aud_check_cart as (
    SELECT 
        id
    FROM 
        datalake_wololo_clean.prospect_aud 
    WHERE 
        status = 'PORTFOLIO'
),
sf_dedup AS (
  SELECT 
      id_lead, 
      MAX(dt_updated) AS dt_updated_latest
  FROM 
      datalake_salesforce_growth_clean.lead
  GROUP BY 
      id_lead
),

sf AS ( -- fl_carteirizado
    SELECT DISTINCT
        sf.id_lead AS lead_id,        
        DATE(sf.creation_date) AS dt_creation_sf,
        sf.channel AS channel_sf,
        u.email AS analyst_email,
        'carteirizado' AS outbound_operation
    FROM 
        datalake_salesforce_growth_clean.lead sf
    LEFT JOIN 
        sf_dedup sfd
            ON sf.id_lead = sfd.id_lead
            AND sf.dt_updated = sfd.dt_updated_latest
    LEFT JOIN 
        datalake_salesforce_growth_clean.user u
            ON sf.id_analyst = u.id_user_salesforce
    WHERE 
        DATE(sf.creation_date) BETWEEN DATE'2025-01-01' AND CURRENT_DATE
),

cohort_events AS (
    SELECT 
        date,
        sk_supply,
        nm_business_context,
        cd_funnel_step
    FROM 
        dw_growth.obt_supply
    WHERE 
        cd_funnel_step IN ('qualified','opportunity','first_listing')
),

campaign_name_historic_dictionary AS ( 
    SELECT 
        id_campaign, 
        campaign_name, 
        ROW_NUMBER() OVER(PARTITION BY campaign_name ORDER BY dt_start ASC) AS campaign_name_order, -- campanhas com nomes iguais e id_campaign diferentes devem ser unificados em uma mesma campanha. Para isso, elas são ordenadas e é selecionada o 1˚ ID das campanhas de mesma UTM.
        is_current
    FROM 
        datalake_growth_media_platform.campaign_name_history
),

latest_campaign_name AS ( 
    SELECT 
        * 
    FROM (
      SELECT
          id_campaign, 
          campaign_name, 
          ROW_NUMBER() OVER(PARTITION BY id_campaign ORDER BY dt_end DESC NULLS FIRST, dt_start DESC) AS campaign_id_order
      FROM 
          datalake_growth_media_platform.campaign_name_history
      ) 
      WHERE 
          TRUE 
          AND campaign_id_order = 1
),

actual_vol AS (
    SELECT 
      'actual_vol' as aux_reference,
        obt.date
        ,obt.acquisition_origin
        ,obt.nm_business_context AS business_context
        ,obt.nm_supply_source AS supply_source
        ,obt.company_report_origin
        ,obt.planning_operation
        ,obt.planning_conversion
        ,obt.planning_cluster
        ,obt.behavior_type
        ,obt.source
        ,obt.medium
        ,obt.nm_campaign
        ,cnh.id_campaign
        ,obt.country_code
        ,obt.city_group
        ,obt.ds_discard_reason
        ,scc.campaign_cluster
        ,sf.dt_creation_sf
        ,sf.channel_sf
        ,CASE 
            WHEN ac.id IS NOT NULL 
                AND obt.country_code = 'BR' 
                AND obt.planning_operation = 'Outbound'
                AND NOT (
                    obt.date >= DATE '2025-09-01' 
                        AND obt.nm_business_context = 'RENT' 
                        AND (
                        obt.sk_user_conversion IN (8919771, 11299701, 6001450) OR
                        obt.sk_user_conversion IN (8919771, 11299701, 6001450) OR
                        obt.sk_user_affiliate IN (12306405, 14046860, 14053116,14046994, 14217303, 14294994)
                        )
                    )
                THEN TRUE 
            ELSE FALSE
        END AS is_carteirizacao
        ,CASE
            WHEN obt.sk_user_conversion IS NULL 
                THEN NULL
            WHEN obt.sk_user_conversion IN ( 
              12524938,13946547,8213735,13345718,12547541,13686088,13096943,12514676,14248042,13650603,14077391,13089199,
              13686095,12525058,13345712,12547601,13180531,13044261,13686090,8629756,10461327,8629755,12839526,13201490,
              13892168,13817190,13180530,13473187,13946548,13473192,12080523,12422745,12525005,13395938,13276220,14473223,
              8793348,13501526,13158267,12013178,12839533,9840974,13390240,12458723,13390237,1479808,13460993,14473225,13658514,
              13096941,12547669
              )
              AND NOT (
                  obt.date >= DATE '2025-09-01' AND obt.nm_business_context = 'RENT' 
                  AND (
                      obt.sk_user_conversion IN (8919771, 11299701, 6001450) OR
                      obt.sk_user_conversion IN (8919771, 11299701, 6001450) OR
                      obt.sk_user_affiliate IN (12306405, 14046860, 14053116,14046994, 14217303, 14294994)
                      )
                  )
                  AND obt.country_code = 'BR' 
                  AND obt.planning_operation = 'Outbound'
                  THEN TRUE 
              ELSE FALSE
        END AS is_exec_carteirizacao
        ,CASE
            WHEN obt.date >= DATE '2025-09-01' 
              AND obt.date <= DATE '2025-11-18' 
              AND obt.nm_business_context = 'RENT' 
              AND obt.sk_user_conversion IN (8919771, 11299701, 6001450) 
              THEN TRUE
            WHEN obt.date >= DATE '2025-09-01' 
              AND obt.date <= DATE '2025-11-18' 
              AND obt.nm_business_context = 'RENT' 
              AND obt.sk_user_affiliate IN (12306405, 14046860,14053116, 14046994, 14217303, 14294994) 
              THEN TRUE
            WHEN obt.date >= DATE '2025-09-01' 
              AND obt.nm_business_context = 'RENT' 
              AND lower(obt.nm_agent) IN ('ciq_pj', '3p_fr') 
              THEN TRUE
            ELSE FALSE
        END AS is_3p_fr_test
        ,CASE 
          WHEN obt.nm_campaign = '-1' AND ia.source_environment IN (
            'isaias_inbound_main', 'isaias_inbound_c2wa_acq_1', 'isaias_inbound_c2wa_acq_2',
            'isaias_inbound_c2wa_retarg_1', 'isaias_inbound_c2wa_retarg_2', 'isaias_inbound_c2wa_camp_1',
            'isaias_inbound_c2wa_camp_2', 'isaias_inbound_c2wa_camp_3', 'isaias_inbound_c2wa_camp_4'
            ) THEN TRUE 
          WHEN obt.nm_campaign IN (
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[others_cities][inbound][objective:engagement][number:1150393202]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[others_cities][inbound][objective:engagement][number:50281715]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[others_cities][inbound][objective:venda][number:1150393202]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[others_cities][inbound][objetivo_venda][number:1150281715]',
            's048s.rent.acq.nonorg.ownlan.s.semnon-branded.google.[all_cities][pwa][high_intention_kw][whatsapp_inbound][number:1150282302]',
            's048s.rent.acq.nonorg.ownlan.s.semnon-branded.google.[others_cities][pwa][high_intention_kw]',
            's050s.hybr.ret.nonorg.inb.s.whatsapp.facebook.[others_cities][inbound][objective:engagement][number:1150267073]',
            's050s.hybr.ret.nonorg.inb.s.whatsapp.facebook.[others_cities][inbound][objective:engagement][number:1150395879]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[all_cities][inbound][objective:engagement][isaias][number:1150267073]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[others_cities][inbound][objective:engagement][number:1150282302]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[all_cities][inbound][objective:engagement][number:1150391395]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[all_cities][inbound][objective:engagement][only_reels][number:1150267057]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[all_cities][inbound][objective:engagement][all_placements][number:1150280247]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[all_cities][inbound][objective:engagement][number:1150397149]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[all_cities][inbound][objective:engagement][adv+][number:1150391395]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[all_cities][inbound][objective:engagement][prospects_ht][number:1150391395]',
            's050s.hybr.ret.nonorg.inb.s.whatsapp.facebook.[all_cities]inbound][objective:venda][prospects_ht][number:1138108981]',
            's050s.hybr.acq.nonorg.inb.s.whatsapp.facebook.[all_cities][inbound][objective:engagement][prospects_ht][number:1150267057]',
            's050s.hybr.eng.nonorg.inb.s.whatsapp.facebook.[others_cities][inbound][objective:engagement][number:1150395879]',
            's050s.hybr.eng.nonorg.inb.s.whatsapp.facebook.[all_cities]inbound][objective:venda][prospects_ht][number:1138108981]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[all_cities][inbound][objective:sales][prospects_ctwa][number:1150280247]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[all_cities][inbound][objective:sales][qualifields_ht][number:1150280247]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[all_cities][inbound][objective:sales][qualifields_ht][number:1150281715]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[others_cities][inbound][objective:engagement][copy][number:1150281715]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[all_cities][inbound][objective:sales][prospects_ht][number:1150391395]',
            's050s.hybr.eng.nonorg.inb.s.webdisplay.facebook.[others_cities][inbound][objective:engagement][number:1150395879]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[all_cities][inbound][objective:sales][prospects_ht][number:1150280247]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[all_cities][inbound][objective:sales][prospects_ht][number:1150281715]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[all_cities][inbound][objective:sales][click2call][number:1150391395]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[all_cities][inbound][objective:sales][prospects_ht][number:1150397149]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[all_cities][inbound][objective:sales][prospects_ht][number:1150267057]',
            '39.hybr.acq.nonorg.inb.s.webdisplay.facebook.[sao_paulo][inbound][objective:sales][prospects_ht][calc][number:1150280247]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[others_cities][inbound][objective:engagement][number:1150393202]',
            's050s.hybr.eng.nonorg.inb.s.webdisplay.facebook.[all_cities]inbound][objective:venda][prospects_ht][number:1138108981]',
            's050s.hybr.acq.nonorg.inb.s.webdisplay.facebook.[all_cities][inbound][objective:sales][prospects_ht][number:1150281715][relaunch]'
            ) THEN TRUE
          WHEN obt.quinto_andar_phone_number IN (
            '551138108981', '551150267057', '551150280247', '551150281715',
            '551150391395', '551150393202', '551150395879', '551150397149'
            ) THEN TRUE
          ELSE FALSE 
        END AS is_click_to_wpp
        ,COALESCE(sf.outbound_operation, 'não-carteirizado') as outbound_operation
        ,COALESCE(fl_unique.fl_unique, 'Cross-listing') as fl_unique
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'lead', obt.sk_supply, NULL))) as act_leads
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect', obt.sk_supply, NULL))) as act_prospects
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'qualified', obt.sk_supply, NULL))) as act_qualifieds
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'av_qualified', obt.sk_supply, NULL))) as act_av_qualifieds
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'opportunity', obt.sk_supply, NULL))) as act_opportunities
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'first_listing', obt.sk_supply, NULL))) as act_first_listings
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect', qualifieds.sk_supply, NULL))) as qty_p2q_cohort
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect', opportunities.sk_supply, NULL))) as qty_p2o_cohort
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect', first_listings.sk_supply, NULL))) as qty_p2l_cohort
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and datediff(qualifieds.date, obt.date)<=7, qualifieds.sk_supply, NULL))) as    qty_p2q_cohort_d7
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and datediff(opportunities.date, obt.date)<=7, opportunities.sk_supply, NULL))) as    qty_p2o_cohort_d7
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and datediff(first_listings.date, obt.date)<=7, first_listings.sk_supply, NULL))) as    qty_p2l_cohort_d7
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and datediff(qualifieds.date, obt.date)<=14, qualifieds.sk_supply, NULL))) as     qty_p2q_cohort_d14
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and datediff(opportunities.date, obt.date)<=14, opportunities.sk_supply, NULL))) as     qty_p2o_cohort_d14
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and datediff(first_listings.date, obt.date)<=14, first_listings.sk_supply, NULL)))  as   qty_p2l_cohort_d14
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and datediff(qualifieds.date, obt.date)<=28, qualifieds.sk_supply, NULL))) as     qty_p2q_cohort_d28
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and datediff(opportunities.date, obt.date)<=28, opportunities.sk_supply, NULL))) as     qty_p2o_cohort_d28
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and datediff(first_listings.date, obt.date)<=28, first_listings.sk_supply, NULL)))  as   qty_p2l_cohort_d28
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and date_trunc('WEEK', qualifieds.date) = date_trunc('WEEK', obt.date), qualifieds.   sk_supply, NULL))) as qty_p2q_cohort_w0
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and date_trunc('WEEK', opportunities.date) = date_trunc('WEEK', obt.date),    opportunities.sk_supply, NULL))) as qty_p2o_cohort_w0
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'prospect' and date_trunc('WEEK', first_listings.date) = date_trunc('WEEK', obt.date),     first_listings.sk_supply, NULL))) as qty_p2l_cohort_w0
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'opportunity', first_listings.sk_supply, NULL))) as qty_o2l_cohort
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'opportunity' and datediff(first_listings.date, obt.date)<=7, first_listings.sk_supply, NULL)))  as   qty_o2l_cohort_d7
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'opportunity' and datediff(first_listings.date, obt.date)<=14, first_listings.sk_supply,   NULL)))   as qty_o2l_cohort_d14
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'opportunity' and datediff(first_listings.date, obt.date)<=28, first_listings.sk_supply,   NULL)))   as qty_o2l_cohort_d28
        ,COUNT(DISTINCT (IF(obt.cd_funnel_step = 'opportunity' and date_trunc('WEEK', first_listings.date) = date_trunc('WEEK', obt.date),    first_listings.sk_supply, NULL))) as qty_o2l_cohort_w0
        ,NULL AS lastyear_leads
        ,NULL AS lastyear_prospects 
        ,NULL AS lastyear_opportunities
        ,NULL AS lastyear_first_listings
        ,NULL AS bup_prospects
        ,NULL AS bup_qualifieds
        ,NULL AS bup_opportunities
        ,NULL AS bup_first_listings
        ,NULL AS okr_prospects
        ,NULL AS okr_qualifieds
        ,NULL AS okr_opportunities
        ,NULL AS okr_first_listings
        ,NULL AS qts_prospects_unique
        ,NULL AS qts_qualifieds_unique
        ,NULL AS qts_opportunities_unique
        ,NULL AS qts_first_listings_unique
        ,NULL AS tgt_cost
        ,NULL AS mkt_cost
    FROM 
      dw_growth.obt_supply obt
    LEFT JOIN 
      cohort_events qualifieds 
        ON obt.sk_supply = qualifieds.sk_supply 
        AND obt.nm_business_context = qualifieds.nm_business_context 
        AND qualifieds.cd_funnel_step =  'qualified'
    LEFT JOIN 
      cohort_events opportunities 
        ON obt.sk_supply = opportunities.sk_supply 
        AND obt.nm_business_context = opportunities.nm_business_context 
        AND opportunities.cd_funnel_step = 'opportunity'
    LEFT JOIN 
      cohort_events first_listings 
        ON obt.sk_supply = first_listings.sk_supply 
        AND obt.nm_business_context = first_listings.nm_business_context 
        AND first_listings.cd_funnel_step = 'first_listing'
    LEFT JOIN 
      datalake_supply_staging.supply_unique_rules fl_unique
        ON obt.sk_supply = fl_unique.sk_supply 
        AND obt.nm_business_context = fl_unique.nm_business_context
    LEFT JOIN 
      datalake_gsheets_clean.supply_campaign_cluster AS scc
        ON LOWER(obt.campaign_strategy_intent) = LOWER(scc.campaign_strategy_intent)
        AND LOWER(obt.campaign_business_context) = LOWER(scc.campaign_business_context) 
        AND LOWER(obt.source) = LOWER(scc.source)
        AND LOWER(obt.medium) = LOWER(scc.medium)
        AND LOWER(obt.behavior_type) = LOWER(scc.behavior_type)
        AND LOWER(obt.funnel_side) = LOWER(scc.funnel_side)
        AND LOWER(obt.campaign_landing_page) = LOWER(scc.campaign_landing_page)
    LEFT JOIN 
      campaign_name_historic_dictionary AS cnh 
        ON cnh.campaign_name = obt.nm_campaign
        AND cnh.campaign_name_order = 1
    LEFT JOIN 
      sf 
        ON obt.sk_lead = sf.lead_id
    LEFT JOIN
      datalake_wololo_clean.prospect p
        ON p.id_reference = obt.sk_lead
    LEFT JOIN 
      aud_check_cart ac
        ON ac.id = p.id
    LEFT JOIN 
      datalake_supply_flows.inbound_attribution AS ia
        ON ia.id_lead_ebdb = obt.sk_lead

    WHERE 
      YEAR(obt.date) >= YEAR(current_date) - 3

    GROUP BY ALL
),

bup AS (
    SELECT 
        'bup' AS aux_reference,
        date
        ,NULL AS acquisition_origin
        ,business_context
        ,CASE 
            WHEN planning_operation = 'Rede' THEN '3P'
            WHEN planning_operation = 'CIQ' THEN 'CIQ'
            ELSE '1P' 
        END AS supply_source
        ,company_report_origin
        ,planning_operation
        ,planning_conversion
        ,planning_cluster
        ,NULL AS behavior_type
        ,NULL AS source
        ,NULL AS medium
        ,NULL AS nm_campaign
        ,NULL AS id_campaign
        ,'BR' AS country_code
        ,city_group
        ,NULL AS ds_discard_reason
        ,NULL AS campaign_cluster
        ,NULL AS dt_creation_sf
        ,NULL AS channel_sf
        ,NULL AS is_carteirizacao
        ,NULL AS is_exec_carteirizacao
        ,NULL AS is_3p_fr_test
        ,NULL AS is_click_to_wpp
        ,NULL AS outbound_operation
        ,NULL AS fl_unique
        ,NULL AS act_leads
        ,NULL AS act_prospects
        ,NULL AS act_qualifieds
        ,NULL AS act_av_qualifieds
        ,NULL AS act_opportunities
        ,NULL AS act_first_listings
        ,NULL AS qty_p2q_cohort
        ,NULL AS qty_p2o_cohort
        ,NULL AS qty_p2l_cohort
        ,NULL AS qty_p2q_cohort_d7
        ,NULL AS qty_p2o_cohort_d7
        ,NULL AS qty_p2l_cohort_d7
        ,NULL AS qty_p2q_cohort_d14
        ,NULL AS qty_p2o_cohort_d14
        ,NULL AS qty_p2l_cohort_d14
        ,NULL AS qty_p2q_cohort_d28
        ,NULL AS qty_p2o_cohort_d28
        ,NULL AS qty_p2l_cohort_d28
        ,NULL AS qty_p2q_cohort_w0
        ,NULL AS qty_p2o_cohort_w0
        ,NULL AS qty_p2l_cohort_w0
        ,NULL AS qty_o2l_cohort
        ,NULL AS qty_o2l_cohort_d7
        ,NULL AS qty_o2l_cohort_d14
        ,NULL AS qty_o2l_cohort_d28
        ,NULL AS qty_o2l_cohort_w0
        ,NULL AS lastyear_leads
        ,NULL AS lastyear_prospects 
        ,NULL AS lastyear_opportunities
        ,NULL AS lastyear_first_listings
        ,SUM(prospects) AS bup_prospects
        ,SUM(qualifieds) AS bup_qualifieds
        ,SUM(opportunities) AS bup_opportunities
        ,SUM(first_listings) AS bup_first_listings
        ,NULL AS okr_prospects
        ,NULL AS okr_qualifieds
        ,NULL AS okr_opportunities
        ,NULL AS okr_first_listings
        ,NULL AS qts_prospects_unique
        ,NULL AS qts_qualifieds_unique
        ,NULL AS qts_opportunities_unique
        ,NULL AS qts_first_listings_unique
        ,NULL AS tgt_cost
        ,NULL AS mkt_cost
    FROM 
        datalake_supply_staging.supply_targets
    WHERE 
        source = 'qts' -- BUP  | budget para OKR
        AND YEAR(date) = YEAR(current_date) 
    GROUP BY ALL
),
okr AS (
    SELECT 
        'okr' AS aux_reference,
        date
        ,NULL AS acquisition_origin
        ,business_context
        ,CASE 
          WHEN planning_operation = 'Rede' THEN '3P'
          WHEN planning_operation = 'CIQ' THEN 'CIQ'
          ELSE '1P' 
        END AS supply_source
        ,CASE
            WHEN planning_cluster LIKE 'Indica Aí - General%' THEN 'Indica Aí - General'
            WHEN planning_cluster LIKE 'Owner PWA - Paid%' THEN 'Owner PWA - Paid'
            WHEN planning_cluster LIKE 'Price Calculator - Sale%' THEN 'Price Calculator - Sale'
            WHEN planning_cluster LIKE 'Price Calculator%' THEN 'Price Calculator'
            ELSE planning_cluster
        END AS company_report_origin
        ,planning_operation
        ,planning_conversion
        ,planning_cluster
        ,NULL AS behavior_type
        ,NULL AS source
        ,NULL AS medium
        ,NULL AS nm_campaign
        ,NULL AS id_campaign
        ,'BR' AS country_code
        ,city_group
        ,NULL AS ds_discard_reason
        ,NULL AS campaign_cluster
        ,NULL AS dt_creation_sf
        ,NULL AS channel_sf
        ,NULL AS is_carteirizacao
        ,NULL AS is_exec_carteirizacao
        ,NULL AS is_3p_fr_test
        ,NULL AS is_click_to_wpp
        ,NULL AS outbound_operation
        ,NULL AS fl_unique
        ,NULL AS act_leads
        ,NULL AS act_prospects
        ,NULL AS act_qualifieds
        ,NULL AS act_av_qualifieds
        ,NULL AS act_opportunities
        ,NULL AS act_first_listings
        ,NULL AS qty_p2q_cohort
        ,NULL AS qty_p2o_cohort
        ,NULL AS qty_p2l_cohort
        ,NULL AS qty_p2q_cohort_d7
        ,NULL AS qty_p2o_cohort_d7
        ,NULL AS qty_p2l_cohort_d7
        ,NULL AS qty_p2q_cohort_d14
        ,NULL AS qty_p2o_cohort_d14
        ,NULL AS qty_p2l_cohort_d14
        ,NULL AS qty_p2q_cohort_d28
        ,NULL AS qty_p2o_cohort_d28
        ,NULL AS qty_p2l_cohort_d28
        ,NULL AS qty_p2q_cohort_w0
        ,NULL AS qty_p2o_cohort_w0
        ,NULL AS qty_p2l_cohort_w0
        ,NULL AS qty_o2l_cohort
        ,NULL AS qty_o2l_cohort_d7
        ,NULL AS qty_o2l_cohort_d14
        ,NULL AS qty_o2l_cohort_d28
        ,NULL AS qty_o2l_cohort_w0
        ,NULL AS lastyear_leads
        ,NULL AS lastyear_prospects 
        ,NULL AS lastyear_opportunities
        ,NULL AS lastyear_first_listings
        ,NULL AS bup_prospects
        ,NULL AS bup_qualifieds
        ,NULL AS bup_opportunities
        ,NULL AS bup_first_listings
        ,SUM(prospects) AS okr_prospects
        ,SUM(qualifieds) AS okr_qualifieds
        ,SUM(opportunities) AS okr_opportunities
        ,SUM(first_listings) AS okr_first_listings
        ,NULL AS qts_prospects_unique
        ,NULL AS qts_qualifieds_unique
        ,NULL AS qts_opportunities_unique
        ,NULL AS qts_first_listings_unique
        ,NULL AS tgt_cost
        ,NULL AS mkt_cost
    FROM 
        datalake_supply_staging.supply_targets
    WHERE 
        source = 'okr' -- BUP  | budget para OKR
        AND YEAR(date) = YEAR(current_date) 
    GROUP BY ALL
),
tgt_unique as (
    SELECT 
        'target_unique' AS aux_reference,
        date
        ,NULL AS acquisition_origin
        ,NULL AS business_context
        ,CASE 
            WHEN planning_operation = 'Rede' THEN '3P'
            WHEN planning_operation = 'CIQ' THEN 'CIQ'
            ELSE '1P' 
        END AS supply_source
        ,company_report_origin
        ,planning_operation
        ,planning_conversion
        ,planning_cluster
        ,NULL AS behavior_type
        ,NULL AS source
        ,NULL AS medium
        ,NULL AS nm_campaign
        ,NULL AS id_campaign
        ,'BR' AS country_code
        ,city_group
        ,NULL AS ds_discard_reason
        ,campaign_cluster
        ,NULL AS dt_creation_sf
        ,NULL AS channel_sf
        ,NULL AS is_carteirizacao
        ,NULL AS is_exec_carteirizacao
        ,NULL AS is_3p_fr_test
        ,NULL AS is_click_to_wpp
        ,NULL AS outbound_operation
        ,'Unique' AS fl_unique
        ,NULL AS act_leads
        ,NULL AS act_prospects
        ,NULL AS act_qualifieds
        ,NULL AS act_av_qualifieds
        ,NULL AS act_opportunities
        ,NULL AS act_first_listings
        ,NULL AS qty_p2q_cohort
        ,NULL AS qty_p2o_cohort
        ,NULL AS qty_p2l_cohort
        ,NULL AS qty_p2q_cohort_d7
        ,NULL AS qty_p2o_cohort_d7
        ,NULL AS qty_p2l_cohort_d7
        ,NULL AS qty_p2q_cohort_d14
        ,NULL AS qty_p2o_cohort_d14
        ,NULL AS qty_p2l_cohort_d14
        ,NULL AS qty_p2q_cohort_d28
        ,NULL AS qty_p2o_cohort_d28
        ,NULL AS qty_p2l_cohort_d28
        ,NULL AS qty_p2q_cohort_w0
        ,NULL AS qty_p2o_cohort_w0
        ,NULL AS qty_p2l_cohort_w0
        ,NULL AS qty_o2l_cohort
        ,NULL AS qty_o2l_cohort_d7
        ,NULL AS qty_o2l_cohort_d14
        ,NULL AS qty_o2l_cohort_d28
        ,NULL AS qty_o2l_cohort_w0
        ,NULL AS lastyear_leads
        ,NULL AS lastyear_prospects 
        ,NULL AS lastyear_opportunities
        ,NULL AS lastyear_first_listings
        ,NULL AS bup_prospects
        ,NULL AS bup_qualifieds
        ,NULL AS bup_opportunities
        ,NULL AS bup_first_listings
        ,NULL AS okr_prospects
        ,NULL AS okr_qualifieds
        ,NULL AS okr_opportunities
        ,NULL AS okr_first_listings
        ,SUM(volumes_prospects_unique) AS qts_prospects_unique
        ,SUM(volumes_qualifieds_unique) AS qts_qualifieds_unique
        ,SUM(volumes_opportunities_unique) AS qts_opportunities_unique
        ,SUM(volumes_first_listings_unique) AS qts_first_listings_unique
        ,NULL AS tgt_cost
        ,NULL AS mkt_cost
    FROM 
        datalake_supply_staging.supply_unique_targets
    GROUP BY ALL
),
tgt_mkt_costs AS (
    SELECT 
        'tgt_mkt_costs' AS aux_reference, 
        dt_target AS date,
        NULL AS acquisition_origin,
        'SALE' AS business_context,
        '1P' AS supply_source,
        CASE
            WHEN supply_origin LIKE 'Owner PWA' THEN 'Owner PWA - Paid'
            ELSE supply_origin
        END AS company_report_origin,
        NULL AS planning_operation,
        NULL AS planning_conversion,
        NULL AS planning_cluster,
        NULL AS behavior_type,
        NULL AS source,
        supply_medium AS medium,
        NULL AS nm_campaign,
        NULL AS id_campaign,
        NULL AS country_code,
        city_group,
        NULL AS ds_discard_reason,
        NULL AS campaign_cluster,
        NULL AS dt_creation_sf,
        NULL AS channel_sf,
        NULL AS is_carteirizacao,
        NULL AS is_exec_carteirizacao,
        NULL AS is_3p_fr_test,
        NULL AS is_click_to_wpp,
        NULL AS outbound_operation,
        'Unique' AS fl_unique,
        NULL AS act_leads,
        NULL AS act_prospects,
        NULL AS act_qualifieds,
        NULL AS act_av_qualifieds,
        NULL AS act_opportunities,
        NULL AS act_first_listings,
        NULL AS qty_p2q_cohort,
        NULL AS qty_p2o_cohort,
        NULL AS qty_p2l_cohort,
        NULL AS qty_p2q_cohort_d7,
        NULL AS qty_p2o_cohort_d7,
        NULL AS qty_p2l_cohort_d7,
        NULL AS qty_p2q_cohort_d14,
        NULL AS qty_p2o_cohort_d14,
        NULL AS qty_p2l_cohort_d14,
        NULL AS qty_p2q_cohort_d28,
        NULL AS qty_p2o_cohort_d28,
        NULL AS qty_p2l_cohort_d28,
        NULL AS qty_p2q_cohort_w0,
        NULL AS qty_p2o_cohort_w0,
        NULL AS qty_p2l_cohort_w0,
        NULL AS qty_o2l_cohort,
        NULL AS qty_o2l_cohort_d7,
        NULL AS qty_o2l_cohort_d14,
        NULL AS qty_o2l_cohort_d28,
        NULL AS qty_o2l_cohort_w0,
        NULL AS lastyear_leads,
        NULL AS lastyear_prospects,
        NULL AS lastyear_opportunities,
        NULL AS lastyear_first_listings,
        NULL AS bup_prospects,
        NULL AS bup_qualifieds,
        NULL AS bup_opportunities,
        NULL AS bup_first_listings,
        NULL AS okr_prospects,
        NULL AS okr_qualifieds,
        NULL AS okr_opportunities,
        NULL AS okr_first_listings,
        NULL AS qts_prospects_unique,
        NULL AS qts_qualifieds_unique,
        NULL AS qts_opportunities_unique,
        NULL AS qts_first_listings_unique,
        SUM(cost_per_source) AS tgt_cost,
        NULL AS mkt_cost
    FROM 
        datalake_gsheets_clean.daily_target_supply_sale
    WHERE 
        cost_per_source > 0
        AND YEAR(dt_target) = YEAR(CURRENT_DATE) 
    GROUP BY ALL
UNION ALL
    SELECT 
        'tgt_mkt_costs' AS aux_reference, 
        dt_target AS date,
        NULL AS acquisition_origin,
        'RENT' AS business_context,
        '1P' AS supply_source,
        CASE
            WHEN supply_origin like 'Owner PWA' THEN 'Owner PWA - Paid'
            ELSE supply_origin
        END AS company_report_origin,
        NULL AS planning_operation,
        NULL AS planning_conversion,
        NULL AS planning_cluster,
        NULL AS behavior_type,
        NULL AS source,
        supply_medium AS medium,
        NULL AS nm_campaign,
        NULL AS id_campaign,
        NULL AS country_code,
        city_group,
        NULL AS ds_discard_reason,
        NULL AS campaign_cluster,
        NULL AS dt_creation_sf,
        NULL AS channel_sf,
        NULL AS is_carteirizacao,
        NULL AS is_exec_carteirizacao,
        NULL AS is_3p_fr_test,
        NULL AS is_click_to_wpp,
        NULL AS outbound_operation,
        'Unique' AS fl_unique,
        NULL AS act_leads,
        NULL AS act_prospects,
        NULL AS act_qualifieds,
        NULL AS act_av_qualifieds,
        NULL AS act_opportunities,
        NULL AS act_first_listings,
        NULL AS qty_p2q_cohort,
        NULL AS qty_p2o_cohort,
        NULL AS qty_p2l_cohort,
        NULL AS qty_p2q_cohort_d7,
        NULL AS qty_p2o_cohort_d7,
        NULL AS qty_p2l_cohort_d7,
        NULL AS qty_p2q_cohort_d14,
        NULL AS qty_p2o_cohort_d14,
        NULL AS qty_p2l_cohort_d14,
        NULL AS qty_p2q_cohort_d28,
        NULL AS qty_p2o_cohort_d28,
        NULL AS qty_p2l_cohort_d28,
        NULL AS qty_p2q_cohort_w0,
        NULL AS qty_p2o_cohort_w0,
        NULL AS qty_p2l_cohort_w0,
        NULL AS qty_o2l_cohort,
        NULL AS qty_o2l_cohort_d7,
        NULL AS qty_o2l_cohort_d14,
        NULL AS qty_o2l_cohort_d28,
        NULL AS qty_o2l_cohort_w0,
        NULL AS lastyear_leads,
        NULL AS lastyear_prospects,
        NULL AS lastyear_opportunities,
        NULL AS lastyear_first_listings,
        NULL AS bup_prospects,
        NULL AS bup_qualifieds,
        NULL AS bup_opportunities,
        NULL AS bup_first_listings,
        NULL AS okr_prospects,
        NULL AS okr_qualifieds,
        NULL AS okr_opportunities,
        NULL AS okr_first_listings,
        NULL AS qts_prospects_unique,
        NULL AS qts_qualifieds_unique,
        NULL AS qts_opportunities_unique,
        NULL AS qts_first_listings_unique,
        SUM(cost_per_source) AS tgt_cost,
        NULL AS mkt_cost
     FROM 
        datalake_gsheets_clean.daily_target_supply_rental
     WHERE 
        cost_per_source > 0
        AND YEAR(dt_target) = YEAR(CURRENT_DATE) 
     GROUP BY ALL
),
act_costs AS (
    SELECT 
        'act_costs' AS aux_reference, 
        sca.date,
        NULL AS acquisition_origin,
        NULL AS business_context,
        NULL AS supply_source,
        sca.company_report_origin,
        NULL AS planning_operation,
        NULL AS planning_conversion,
        sca.planning_cluster,
        sca.behavior_type,
        sca.source,
        sca.medium,
        sca.nm_campaign,
        sca.id_campaign, 
        'BR' AS country_code,
        sca.city_group,
        NULL AS ds_discard_reason,
        scc.campaign_cluster,
        NULL AS dt_creation_sf,
        NULL AS channel_sf,
        NULL AS is_carteirizacao,
        NULL AS is_exec_carteirizacao,
        NULL AS is_3p_fr_test,
        NULL AS is_click_to_wpp,
        NULL AS outbound_operation,
        'Unique' AS fl_unique,
        NULL AS act_leads,
        NULL AS act_prospects,
        NULL AS act_qualifieds,
        NULL AS act_av_qualifieds,
        NULL AS act_opportunities,
        NULL AS act_first_listings,
        NULL AS qty_p2q_cohort,
        NULL AS qty_p2o_cohort,
        NULL AS qty_p2l_cohort,
        NULL AS qty_p2q_cohort_d7,
        NULL AS qty_p2o_cohort_d7,
        NULL AS qty_p2l_cohort_d7,
        NULL AS qty_p2q_cohort_d14,
        NULL AS qty_p2o_cohort_d14,
        NULL AS qty_p2l_cohort_d14,
        NULL AS qty_p2q_cohort_d28,
        NULL AS qty_p2o_cohort_d28,
        NULL AS qty_p2l_cohort_d28,
        NULL AS qty_p2q_cohort_w0,
        NULL AS qty_p2o_cohort_w0,
        NULL AS qty_p2l_cohort_w0,
        NULL AS qty_o2l_cohort,
        NULL AS qty_o2l_cohort_d7,
        NULL AS qty_o2l_cohort_d14,
        NULL AS qty_o2l_cohort_d28,
        NULL AS qty_o2l_cohort_w0,
        NULL AS lastyear_leads,
        NULL AS lastyear_prospects,
        NULL AS lastyear_opportunities,
        NULL AS lastyear_first_listings,
        NULL AS bup_prospects,
        NULL AS bup_qualifieds,
        NULL AS bup_opportunities,
        NULL AS bup_first_listings,
        NULL AS okr_prospects,
        NULL AS okr_qualifieds,
        NULL AS okr_opportunities,
        NULL AS okr_first_listings,    
        NULL AS qts_prospects_unique,
        NULL AS qts_qualifieds_unique,
        NULL AS qts_opportunities_unique,
        NULL AS qts_first_listings_unique,
        NULL AS tgt_cost,
        CASE 
          WHEN date >= date'2026-01-01' AND sca.source = 'Facebook' THEN shared_cost*1.1215
          ELSE shared_cost
        END AS mkt_cost -- adicionando fator devido a novos impostos de 2026
    FROM 
        datalake_supply_staging.supply_costs_allocation_lead sca
    LEFT JOIN 
        datalake_gsheets_clean.supply_campaign_cluster AS scc
            ON LOWER(sca.campaign_strategy_intent) = LOWER(scc.campaign_strategy_intent)
            AND LOWER(sca.campaign_business_context) = LOWER(scc.campaign_business_context) 
            AND LOWER(sca.source) = LOWER(scc.source)
            AND LOWER(sca.medium) = LOWER(scc.medium)
            AND LOWER(sca.behavior_type) = LOWER(scc.behavior_type)
            AND LOWER(sca.funnel_side) = LOWER(scc.funnel_side)
            AND LOWER(sca.campaign_landing_page) = LOWER(scc.campaign_landing_page)
),
  
act_last_year as (
    SELECT 
        'act_last_year' AS aux_reference, 
        date + INTERVAL 1 YEAR AS date,
        acquisition_origin, 
        business_context, 
        supply_source, 
        company_report_origin, 
        planning_operation, 
        planning_conversion, 
        planning_cluster,
        behavior_type, 
        source, 
        medium, 
        nm_campaign, 
        id_campaign, 
        country_code, 
        city_group,
        ds_discard_reason,
        campaign_cluster,
        dt_creation_sf,
        channel_sf,
        is_carteirizacao,
        is_exec_carteirizacao,
        is_3p_fr_test,
        is_click_to_wpp,
        outbound_operation,
        fl_unique,
        NULL AS act_leads, 
        NULL AS act_prospects, 
        NULL AS act_qualifieds, 
        NULL AS act_av_qualifieds, 
        NULL AS act_opportunities, 
        NULL AS act_first_listings,
        NULL AS qty_p2q_cohort,
        NULL AS qty_p2o_cohort,
        NULL AS qty_p2l_cohort,
        NULL AS qty_p2q_cohort_d7,
        NULL AS qty_p2o_cohort_d7,
        NULL AS qty_p2l_cohort_d7,
        NULL AS qty_p2q_cohort_d14,
        NULL AS qty_p2o_cohort_d14,
        NULL AS qty_p2l_cohort_d14,
        NULL AS qty_p2q_cohort_d28,
        NULL AS qty_p2o_cohort_d28,
        NULL AS qty_p2l_cohort_d28,
        NULL AS qty_p2q_cohort_w0,
        NULL AS qty_p2o_cohort_w0,
        NULL AS qty_p2l_cohort_w0,
        NULL AS qty_o2l_cohort,
        NULL AS qty_o2l_cohort_d7,
        NULL AS qty_o2l_cohort_d14,
        NULL AS qty_o2l_cohort_d28,
        NULL AS qty_o2l_cohort_w0,
        act_leads as lastyear_leads, 
        act_prospects as lastyear_prospects, 
        act_opportunities as lastyear_opportunities, 
        act_first_listings as lastyear_first_listings, 
        NULL AS bup_prospects, 
        NULL AS bup_qualifieds, 
        NULL AS bup_opportunities, 
        NULL AS bup_first_listings, 
        NULL AS okr_prospects, 
        NULL AS okr_qualifieds, 
        NULL AS okr_opportunities, 
        NULL AS okr_first_listings,
        NULL AS qts_prospects_unique,
        NULL AS qts_qualifieds_unique,
        NULL AS qts_opportunities_unique,
        NULL AS qts_first_listings_unique, 
        NULL AS tgt_cost, 
        NULL AS mkt_cost
    FROM 
        actual_vol
    WHERE 
        YEAR(date) = YEAR(CURRENT_DATE) -1
)
,consolidated_metrics as (
  SELECT * FROM actual_vol
  UNION ALL
  SELECT * FROM bup
  UNION ALL
  SELECT * FROM okr
  UNION ALL
  SELECT * FROM tgt_unique
  UNION ALL
  SELECT * FROM tgt_mkt_costs
  UNION ALL 
  SELECT * FROM act_costs
  UNION ALL 
  SELECT * FROM act_last_year
)

SELECT 
    m.aux_reference, 
    CAST(m.date AS date) AS date,
    m.acquisition_origin,
    m.business_context,
    m.supply_source,
    m.company_report_origin,
    m.planning_operation,
    m.planning_conversion,
    m.planning_cluster,
    m.behavior_type,
    m.source,
    m.medium,
    COALESCE(cnh.campaign_name,m.nm_campaign) AS nm_campaign,
    m.id_campaign, 
    m.country_code,
    m.city_group,
    m.ds_discard_reason,
    m.campaign_cluster,
    m.dt_creation_sf,
    m.channel_sf,
    m.is_carteirizacao,
    m.is_exec_carteirizacao,
    m.is_3p_fr_test,
    m.is_click_to_wpp,
    m.outbound_operation,
    m.fl_unique,
    m.act_leads,
    m.act_prospects,
    m.act_qualifieds,
    m.act_av_qualifieds,
    m.act_opportunities,
    m.act_first_listings,
    m.qty_p2q_cohort,
    m.qty_p2o_cohort,
    m.qty_p2l_cohort,
    m.qty_p2q_cohort_d7,
    m.qty_p2o_cohort_d7,
    m.qty_p2l_cohort_d7,
    m.qty_p2q_cohort_d14,
    m.qty_p2o_cohort_d14,
    m.qty_p2l_cohort_d14,
    m.qty_p2q_cohort_d28,
    m.qty_p2o_cohort_d28,
    m.qty_p2l_cohort_d28,
    m.qty_p2q_cohort_w0,
    m.qty_p2o_cohort_w0,
    m.qty_p2l_cohort_w0,
    m.qty_o2l_cohort,
    m.qty_o2l_cohort_d7,
    m.qty_o2l_cohort_d14,
    m.qty_o2l_cohort_d28,
    m.qty_o2l_cohort_w0,
    m.lastyear_leads,
    m.lastyear_prospects,
    m.lastyear_opportunities,
    m.lastyear_first_listings,
    m.bup_prospects,
    m.bup_qualifieds,
    m.bup_opportunities,
    m.bup_first_listings,
    m.okr_prospects,
    m.okr_qualifieds,
    m.okr_opportunities,
    m.okr_first_listings,
    m.qts_prospects_unique,
    m.qts_qualifieds_unique,
    m.qts_opportunities_unique,
    m.qts_first_listings_unique,
    m.tgt_cost,
    m.mkt_cost
    ,dd.month_start
    ,dd.week_start
    ,dd.year
    ,(SELECT max_date FROM max_date_obt) AS max_date
    ,CASE
        WHEN WEEKDAY(m.date) < WEEKDAY(max_date) THEN TRUE 
        ELSE FALSE
    END AS WTD
    ,CASE
        WHEN DAY(m.date) <= DAY(max_date) THEN TRUE 
        ELSE FALSE 
    END AS MTD
    ,CASE
        WHEN MONTH(m.date) < MONTH(max_date) OR (
            MONTH(m.date) = MONTH(max_date) AND DAY(m.date) <= DAY(max_date) 
            ) THEN TRUE
        ELSE FALSE
    END AS YTD 
    ,CASE
        WHEN m.date >= DATE_TRUNC('month', max_date) AND DAY(m.date) <= DAY(max_date) THEN TRUE 
        ELSE FALSE 
    END AS MTD_CurrentMonth 
    ,CASE 
        WHEN m.date >= DATE_TRUNC('year', max_date) AND m.date <= max_date 
        THEN TRUE  
        ELSE FALSE  
    END AS YTD_CurrentYear
    , NOW() AS ts_load

FROM 
    consolidated_metrics m
LEFT JOIN 
    dw_public.dim_date AS dd 
        ON dd.date = m.date
LEFT JOIN 
    latest_campaign_name AS cnh
        ON cnh.id_campaign = m.id_campaign

