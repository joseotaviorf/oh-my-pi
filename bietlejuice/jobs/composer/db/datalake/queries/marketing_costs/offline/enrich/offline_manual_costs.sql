WITH offline_costs AS (
    SELECT
        COALESCE(ts_entry,'') ||'-'|| COALESCE(entry_type,'') ||'-'|| COALESCE(email,'') ||'-'|| COALESCE(invoice_number,'') AS aux_key,
        ts_entry,
        email,
        team,
        entry_type,
        invoice_number,
        dt_invoice,
        dt_service_started,
        dt_service_ended,
        cnpj,
        vendor_name,
        description,
        campaign_name,
        cost_category,
        cost_subcategory,
        action,
        business_context,
        CASE 
            WHEN has_cost_center_share = 'Sim' THEN TRUE 
            WHEN has_cost_center_share = 'Não' THEN FALSE
            ELSE NULL
        END AS has_cost_center_share,
        CASE 
            WHEN COALESCE(
                has_city_group_share_1,
                has_city_group_share_2
            ) = 'Sim' THEN TRUE
            WHEN COALESCE(
                has_city_group_share_1,
                has_city_group_share_2
            ) = 'Não' THEN FALSE
            ELSE NULL
        END AS has_city_group_share,
        id_rule_city_group_rent,
        id_rule_city_group_sale,
        city_group,
        id_rule_cost_center,
        cost_center,
        CASE 
            WHEN entry_type = 'Estorno' AND cost > 0 THEN cost * (-1)
            ELSE cost
        END AS cost
    FROM
        datalake_marketing_offline_costs_clean.marketing_offline_manual_costs
),
city_group_rules AS (
    SELECT
        id_rule_city_group,
        city_group,
        share
    FROM
        datalake_marketing_offline_costs_clean.marketing_offline_manual_share_city_group
),
cost_center_rules AS (
    SELECT
        id_rule_cost_center,
        cost_center,
        share
    FROM
        datalake_marketing_offline_costs_clean.marketing_offline_manual_share_cost_center
),
date_range AS (
    SELECT 
        EXPLODE(
            SEQUENCE(
                min(dt_service_started),
                max(dt_service_ended),
                interval 1 day
            )
        ) AS date
    FROM 
      datalake_marketing_offline_costs_clean.marketing_offline_manual_costs
),
aux_invoice_daily_share AS (
    SELECT
        dr.date AS dt_share,
        oc.aux_key, 
        COUNT(dr.date) OVER(PARTITION BY oc.aux_key) AS days_duration
    FROM
        offline_costs oc
        JOIN date_range dr
            ON dr.date BETWEEN dt_service_started AND dt_service_ended  
),
apply_daily_share AS (
    SELECT
        aids.dt_share,
        oc.ts_entry,
        oc.email,
        oc.team,
        oc.entry_type,
        oc.invoice_number,
        oc.dt_invoice,
        oc.dt_service_started,
        oc.dt_service_ended,
        oc.cnpj,
        oc.vendor_name,
        oc.description,
        oc.campaign_name,
        oc.cost_category,
        oc.cost_subcategory,
        oc.action,
        oc.business_context,
        oc.has_city_group_share,
        oc.has_cost_center_share,
        oc.id_rule_city_group_rent,
        oc.id_rule_city_group_sale,
        oc.id_rule_cost_center,
        oc.city_group,
        oc.cost_center,
        oc.cost/aids.days_duration AS daily_cost
    FROM
        offline_costs oc
        LEFT JOIN aux_invoice_daily_share aids
            ON oc.aux_key = aids.aux_key
),
apply_cost_center_share AS (
    SELECT
        ads.dt_share,
        ads.ts_entry,
        ads.email,
        ads.team,
        ads.entry_type,
        ads.invoice_number,
        ads.dt_invoice,
        ads.dt_service_started,
        ads.dt_service_ended,
        ads.cnpj,
        ads.vendor_name,
        ads.description,
        ads.campaign_name,
        ads.cost_category,
        ads.cost_subcategory,
        ads.action,
        ads.business_context,
        ads.has_city_group_share,
        ads.has_cost_center_share,
        ads.id_rule_city_group_rent,
        ads.id_rule_city_group_sale,
        ads.id_rule_cost_center,
        ads.city_group,
        COALESCE(ads.cost_center,ccr.cost_center) AS cost_center,
        ads.daily_cost*COALESCE(ccr.share,1) AS daily_cc_cost
    FROM
        apply_daily_share ads
        LEFT JOIN cost_center_rules ccr
            ON ads.id_rule_cost_center = ccr.id_rule_cost_center
),
apply_city_group_share AS (
    SELECT
        INT(DATE_FORMAT(DATE(accs.dt_share), 'yyyyMMdd')) AS id_date,
        accs.dt_share,
        accs.ts_entry,
        accs.email,
        accs.team,
        accs.entry_type,
        accs.invoice_number,
        accs.dt_invoice,
        accs.dt_service_started,
        accs.dt_service_ended,
        accs.cnpj,
        accs.vendor_name,
        accs.description,
        accs.campaign_name,
        accs.cost_category,
        accs.cost_subcategory,
        accs.action,
        accs.business_context,
        accs.has_city_group_share,
        accs.has_cost_center_share,
        accs.id_rule_city_group_rent,
        accs.id_rule_city_group_sale,
        accs.id_rule_cost_center,
        accs.cost_center,
        COALESCE(accs.city_group,cgr_r.city_group,cgr_s.city_group) AS city_group,
        accs.daily_cc_cost*COALESCE(cgr_r.share,cgr_s.share,1) AS cost
    FROM
        apply_cost_center_share accs
        LEFT JOIN city_group_rules cgr_r
            ON accs.id_rule_city_group_rent = cgr_r.id_rule_city_group
            AND LOWER(accs.cost_center) NOT LIKE '%sale%'
        LEFT JOIN city_group_rules cgr_s
            ON accs.id_rule_city_group_sale = cgr_s.id_rule_city_group
            AND LOWER(accs.cost_center) LIKE '%sale%'
)
SELECT
    MONOTONICALLY_INCREASING_ID() AS id,
    acgs.id_date,
    acgs.id_rule_city_group_rent,
    acgs.id_rule_city_group_sale,
    acgs.id_rule_cost_center,
    acgs.email,
    acgs.team,
    acgs.entry_type,
    acgs.invoice_number,
    acgs.cnpj,
    acgs.vendor_name,
    acgs.description,
    acgs.campaign_name,
    acgs.cost_category,
    acgs.cost_subcategory,
    acgs.action,
    acgs.business_context,
    acgs.has_city_group_share,
    acgs.has_cost_center_share,
    acgs.cost_center,
    acgs.city_group,
    acgs.cost,
    acgs.ts_entry,
    acgs.dt_invoice,
    acgs.dt_service_started,
    acgs.dt_service_ended
FROM
    apply_city_group_share acgs
