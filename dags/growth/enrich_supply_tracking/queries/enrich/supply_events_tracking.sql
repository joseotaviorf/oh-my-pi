WITH conversion_info AS (
    SELECT 
        id_lead AS id_lead_ebdb,
        id_house,
        business_context,
        supply_source
    FROM 
        datalake_supply_flows.conversion_lookup
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_lead, business_context, supply_source ORDER BY db_source, ts_conversion) = 1
),
acquisition AS (
    SELECT
        CONCAT_WS(
            '#',
            acq.funnel_step,
            acq.business_context,
            COALESCE(acq.supply_source, -1),
            COALESCE(acq.id_lead_ebdb, -1),
            COALESCE(acq.id_house, ci.id_house, -1),
            acq.business_event
        ) AS bk_supply,
        acq.sk_supply_lead,
        acq.business_context,
        CAST(acq.id_lead_ebdb AS BIGINT) AS id_lead_ebdb,
        COALESCE(acq.id_house, ci.id_house) AS id_house,
        acq.id_lead,
        acq.id_wololo AS id_prospect,
        acq.id_lead AS id_entity,
        acq.id_referred_by,
        acq.id_region,
        CAST(NULL AS BIGINT) AS id_user_registrant,
        CAST(NULL AS BIGINT) AS id_user_conversion,
        acq.supply_source,
        acq.business_event,
        acq.funnel_step,
        acq.drop_step_reason,
        acq.affiliate_type,
        acq.application,
        acq.landing_page,
        acq.lead_type,
        acq.application AS lead_application,
        acq.medium,
        acq.source,
        acq.platform,
        acq.campaign,
        acq.term,
        acq.content,
        acq.ops_agent,
        acq.ops_approach,
        acq.ops_contact_medium,
        acq.ops_objective,
        acq.ops_partner,
        acq.ops_assigned,
        acq.original_lead,
        acq.reprocessed,
        IF(acq.reprocessed IS NOT NULL, 'lead', NULL) AS reprocessing_entity_type,
        IF(acq.reprocessed IS NOT NULL, 'rene_descartes', NULL) AS reprocessing_table_name,
        acq.database_tracking_campaign AS aux_database_tracking_campaign,
        acq.database_tracking_medium AS aux_database_tracking_medium,
        acq.database_tracking_source AS aux_database_tracking_source,
        acq.database_tracking_term AS aux_database_tracking_term,
        acq.database_tracking_content AS aux_database_tracking_content,
        FALSE AS aux_data_event,
        'T0.0' AS aux_group,
        acq.aux_product_status,
        'acquisition' AS aux_origin_table,
        acq.funnel_level AS aux_funnel_level,
        acq.ts_event AS ts_event_adjusted,
        acq.ts_event AS ts_event_original,
        CAST(NULL AS TIMESTAMP) AS ts_first_discard,
        CAST(NULL AS TIMESTAMP) AS ts_last_discard,
        CAST(NULL AS TIMESTAMP) AS ts_reprocessing_event,
        acq.ts_load,
        YEAR(acq.ts_event) AS year, 
        MONTH(acq.ts_event) AS month, 
        DAY(acq.ts_event) AS day
    FROM
        datalake_supply_flows.acquisition_tracking AS acq
    LEFT JOIN 
        conversion_info AS ci
            ON (acq.id_lead_ebdb = ci.id_lead_ebdb)
            AND (acq.business_context = ci.business_context)
            AND (acq.supply_source = ci.supply_source)
),
conversion_without_leads AS (
    SELECT
        CONCAT_WS(
            '#',
            con.funnel_step,
            con.business_context,
            COALESCE(con.supply_source, -1),
            COALESCE(con.id_lead_ebdb, -1),
            COALESCE(con.id_entity, -1),
            con.business_event
        ) AS bk_supply,
        CAST(NULL AS BIGINT) AS sk_supply_lead,
        con.business_context,
        CAST(con.id_lead_ebdb AS BIGINT) AS id_lead_ebdb,
        con.id_house,
        CAST(NULL AS STRING) AS id_lead,
        con.id_prospect,
        con.id_entity,
        CAST(NULL AS BIGINT) AS id_referred_by,
        con.id_region,
        con.id_user_registrant,
        con.id_user_conversion,
        con.supply_source,
        con.business_event,
        con.funnel_step,
        con.reason AS drop_step_reason,
        CAST(NULL AS STRING) AS affiliate_type,
        con.application,
        CAST(NULL AS STRING) AS landing_page,
        CAST(NULL AS STRING) AS lead_type,
        CAST(NULL AS STRING) AS lead_application,
        CAST(NULL AS STRING) AS medium,
        CAST(NULL AS STRING) AS source,
        CAST(NULL AS STRING) AS platform,
        CAST(NULL AS STRING) AS campaign,
        CAST(NULL AS STRING) AS term,
        CAST(NULL AS STRING) AS content,
        con.ops_agent,
        con.ops_approach,
        con.ops_contact_medium,
        con.ops_objective,
        con.ops_partner,
        CAST(NULL AS STRING) AS ops_assigned,
        CAST(NULL AS BIGINT) AS original_lead,
        con.reprocessed,
        con.reprocessing_entity_type,
        con.reprocessing_table_name,
        CAST(NULL AS STRING) AS aux_database_tracking_campaign,
        CAST(NULL AS STRING) AS aux_database_tracking_medium,
        CAST(NULL AS STRING) AS aux_database_tracking_source,
        CAST(NULL AS STRING) AS aux_database_tracking_term,
        CAST(NULL AS STRING) AS aux_database_tracking_content,
        con.aux_data_event,
        con.aux_group,
        CAST(NULL AS STRING) AS aux_product_status,
        'conversion' AS aux_origin_table,
        con.ts_event_adjusted,
        con.ts_event_original,
        con.ts_first_discard,
        con.ts_last_discard,
        con.ts_reprocessing_event,
        con.ts_load,
        YEAR(con.ts_event_adjusted) AS year, 
        MONTH(con.ts_event_adjusted) AS month, 
        DAY(con.ts_event_adjusted) AS day
    FROM
        datalake_supply_flows.conversion_tracking AS con
    WHERE 
        id_lead_ebdb IS NULL
),
acq_taxonomy AS (
    SELECT 
        acq.id_lead_ebdb,
        acq.sk_supply_lead,
        acq.id_lead,
        acq.id_referred_by,
        acq.supply_source,
        acq.affiliate_type,
        acq.landing_page,
        acq.lead_type,
        acq.application AS lead_application,
        acq.medium,
        acq.source,
        acq.platform,
        acq.campaign,
        acq.term,
        acq.content,
        acq.original_lead,
        acq.ops_assigned,
        acq.aux_database_tracking_campaign,
        acq.aux_database_tracking_medium,
        acq.aux_database_tracking_source,
        acq.aux_database_tracking_term,
        acq.aux_database_tracking_content,
        acq.aux_product_status
    FROM 
        acquisition AS acq 
    WHERE 
        acq.id_lead_ebdb IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY acq.id_lead_ebdb, acq.supply_source ORDER BY acq.aux_funnel_level DESC, acq.ts_event_adjusted DESC) = 1
),
conversion_with_leads AS (
    SELECT
        CONCAT_WS(
            '#',
            con.funnel_step,
            con.business_context,
            COALESCE(con.supply_source, -1),
            COALESCE(con.id_lead_ebdb, -1),
            COALESCE(con.id_entity, -1),
            con.business_event
        ) AS bk_supply,
        acq.sk_supply_lead,
        con.business_context,
        CAST(con.id_lead_ebdb AS BIGINT) AS id_lead_ebdb,
        con.id_house,
        acq.id_lead,
        con.id_prospect,
        con.id_entity,
        acq.id_referred_by,
        con.id_region,
        con.id_user_registrant,
        con.id_user_conversion,
        con.supply_source,
        con.business_event,
        con.funnel_step,
        con.reason AS drop_step_reason,
        acq.affiliate_type,
        con.application,
        acq.landing_page,
        acq.lead_type,
        acq.lead_application,
        acq.medium,
        acq.source,
        acq.platform,
        acq.campaign,
        acq.term,
        acq.content,
        con.ops_agent,
        con.ops_approach,
        con.ops_contact_medium,
        con.ops_objective,
        con.ops_partner,
        acq.ops_assigned,
        acq.original_lead,
        con.reprocessed,
        con.reprocessing_entity_type,
        con.reprocessing_table_name,
        acq.aux_database_tracking_campaign,
        acq.aux_database_tracking_medium,
        acq.aux_database_tracking_source,
        acq.aux_database_tracking_term,
        acq.aux_database_tracking_content,
        con.aux_data_event,
        con.aux_group,
        acq.aux_product_status,
        'conversion' AS aux_origin_table,
        con.ts_event_adjusted,
        con.ts_event_original,
        con.ts_first_discard,
        con.ts_last_discard,
        con.ts_reprocessing_event,
        con.ts_load,
        YEAR(con.ts_event_adjusted) AS year, 
        MONTH(con.ts_event_adjusted) AS month,
        DAY(con.ts_event_adjusted) AS day
    FROM
        datalake_supply_flows.conversion_tracking AS con
    LEFT JOIN 
        acq_taxonomy AS acq
            ON (con.id_lead_ebdb = acq.id_lead_ebdb)
            AND (con.supply_source = acq.supply_source)
    WHERE 
        con.id_lead_ebdb IS NOT NULL
)

SELECT 
    * EXCEPT (aux_funnel_level)
FROM 
    acquisition
UNION ALL
SELECT 
    *
FROM 
    conversion_without_leads
UNION ALL
SELECT 
    *
FROM 
    conversion_with_leads