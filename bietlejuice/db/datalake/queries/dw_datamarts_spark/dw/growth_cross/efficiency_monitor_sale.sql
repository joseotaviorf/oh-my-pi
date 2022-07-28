WITH sale_volumes AS (
    SELECT
        COALESCE(oh.id_offer,fo.sk_offer) AS sk_offer,
        oh.executive_lead,
        oh.status,
        COALESCE(fo.sk_house, h.id_house_quintoandar::bigint) AS sk_house,
        COALESCE(fo.sk_buyer,oh.id_client_cm, oh.id_user_5a) AS sk_buyer,
        CASE
            WHEN oh.offer_flow LIKE '%HUB%' THEN 'HUB'
            WHEN oh.offer_flow = 'CENTRAL' THEN 'CENTRAL'
            ELSE 'DealMaking'
        END AS offer_flow,
        CASE
            WHEN executive_lead = 'Leonardo Monteiro' OR oh.offer_flow = 'HUB_BV_V0' THEN 'HUB Bela Vista'
            WHEN executive_lead = 'Rodrigo Pereira' OR oh.offer_flow = 'HUB_VM_V0' THEN 'HUB Vila Mariana'
            WHEN oh.offer_flow = 'CENTRAL' AND dr.city_group = 'Porto Alegre' THEN 'CENTRAL POA'
            WHEN oh.offer_flow = 'CENTRAL' AND dr.city_group = 'RMSP' THEN 'CENTRAL SP'
            WHEN oh.offer_flow = 'CENTRAL' AND dr.city_group = 'Rio de Janeiro' THEN 'CENTRAL RJ'
            ELSE 'DealMaking'
        END AS offer_flow_detail,
        TRIM(city_group) AS city_group,
        COALESCE(TO_DATE(CAST(fo.sk_offer_submitted_date AS STRING), 'yyyyMMdd'), oh.dt_offer_submitted) AS dt_offer,
        COALESCE(oh.dt_sale_agreement_signed, TO_DATE(CAST(nullif(fo.sk_sale_agreement_signed_date,-1) AS STRING), 'yyyyMMdd')) AS dt_ccv_signed,
        DATEDIFF(COALESCE(TO_DATE(CAST(fo.sk_offer_submitted_date AS STRING), 'yyyyMMdd'), oh.dt_offer_submitted), COALESCE(oh.dt_sale_agreement_signed, TO_DATE(CAST(nullif(fo.sk_sale_agreement_signed_date,-1) AS STRING), 'yyyyMMdd'))) AS days_offer_submitted_to_sale_agreement_signed,
        COALESCE(dsa.sale_price_agreed, oh.sale_price_agreed) AS sale_price_agreed
    FROM
        dw_sale.fact_offers fo
    LEFT JOIN
        dw_sale.dim_sale_agreement dsa
            ON dsa.sk_offer = fo.sk_offer
    FULL OUTER JOIN
        datalake_gsheets_clean.offers_hub_central oh
            ON fo.sk_offer = oh.id_offer
    LEFT JOIN
        datalake_casa_mineira_crm_clean.house h
            ON h.id = oh.id_house_cm
    LEFT JOIN
        dw_sale.fact_listings fl
            ON fl.sk_house = COALESCE(fo.sk_house, h.id_house_quintoandar::bigint)
    LEFT JOIN
        dw_public.dim_region dr
            ON dr.sk_region = fl.sk_region
), grouped_sale_volumes AS (
    SELECT
        DATE_TRUNC('month',dt_ccv_signed) AS dt_ccv,
        city_group,
        COUNT(distinct sk_offer) AS ccv,
        ROUND(COUNT(distinct sk_offer) * 0.7960, 0) AS potential_closed_deals,
        AVG(sale_price_agreed) AS sale_price_agreed
    FROM
        sale_volumes
    WHERE
        DATE_TRUNC('month',dt_ccv_signed) >= '2020-01-01'
        AND dt_ccv_signed IS NOT NULL
        AND city_group IS NOT NULL
        AND city_group <> 'Not Mapped'
    GROUP BY 1, 2
), sale_targets AS (
    SELECT
        DATE_TRUNC('month',DATE(`date`)) AS month_start,
        TRIM(cidade) AS city_group,
        SUM(ccv) AS ccv_target,
        ROUND(SUM(ccv) * 0.7960, 0) AS potential_closed_deals_target
    FROM
        datalake_gsheets_clean.sale_demand_targets
    WHERE
        cidade != 'Belo Horizonte'
        AND `date` BETWEEN '2020-01-01' AND DATE_TRUNC('week',CURRENT_DATE)
    GROUP BY 1,2
), base_act AS (
    SELECT
        DATE(dt_cost) AS dt_cost,
        TRIM(city_group) AS city_group,
        planning_mkt_level1,
        SUM(costs) AS costs
    FROM
        dw_datamarts.marketing_demand_supply_branding_costs
    WHERE
        dt_cost BETWEEN '2020-01-01' AND DATE_TRUNC('week',CURRENT_DATE)
        AND business = 'Sale'
    GROUP BY 1,2,3
), base_tgt AS (
    SELECT
        DATE(dt_created) AS dt_cost,
        TRIM(city_group) AS city_group,
        planning_mkt_level1,
        SUM(monthly_budget) AS budget_mensal
    FROM
        datalake_gsheets_clean.costs_targets
    WHERE
        dt_created BETWEEN '2020-07-01' AND DATE_TRUNC('week',CURRENT_DATE)
        AND business = 'Sale'
    GROUP BY 1,2,3
), base_costs AS (
    SELECT
        COALESCE(a.dt_cost, t.dt_cost) AS dt_reference,
        COALESCE(a.city_group,t.city_group) AS city_group,
        COALESCE(a.planning_mkt_level1, t.planning_mkt_level1) AS planning_mkt_level1,
        SUM(a.costs) AS cost_act,
        SUM(t.budget_mensal) AS budget_mensal
    FROM
        base_act AS a
    FULL OUTER JOIN
        base_tgt AS t
            ON a.dt_cost = t.dt_cost
            AND a.city_group=t.city_group
            AND a.planning_mkt_level1=t.planning_mkt_level1
    GROUP BY 1,2,3
), marketing_costs AS (
    SELECT
        DATE_TRUNC('month',dt_reference) AS dt_month_start,
        city_group,
        planning_mkt_level1 AS classification,
        SUM(CASE WHEN planning_mkt_level1 = 'Demand' THEN cost_act ELSE 0 END) AS demand_cost,
        SUM(CASE WHEN planning_mkt_level1 = 'Supply' THEN cost_act ELSE 0 END) AS supply_cost,
        SUM(CASE WHEN planning_mkt_level1 = 'Branded' THEN cost_act ELSE 0 END) AS branding_cost,
        SUM(CASE WHEN planning_mkt_level1 = 'Demand' THEN budget_mensal ELSE 0 END) AS demand_budget,
        SUM(CASE WHEN planning_mkt_level1 = 'Supply' THEN budget_mensal ELSE 0 END) AS supply_budget,
        SUM(CASE WHEN planning_mkt_level1 = 'Branded' THEN budget_mensal ELSE 0 END) AS branding_budget
    FROM
        base_costs
    WHERE
        dt_reference <= DATE_TRUNC('week',CURRENT_DATE)
    GROUP BY 1, 2, 3
), marketing_costs_date_city AS (
    SELECT
        dt_month_start,
        city_group,
        SUM(demand_cost) AS demand_cost,
        SUM(supply_cost) AS supply_cost,
        SUM(branding_cost) AS branding_cost,
        SUM(demand_budget) AS demand_budget,
        SUM(supply_budget) AS supply_budget,
        SUM(branding_budget) AS branding_budget
    FROM
        marketing_costs
    GROUP BY 1,2
),supply_metric_amortization AS (
    SELECT
        mc.dt_month_start,
        mc.city_group,
        SUM(CASE WHEN ac.month_amortization = 'M+0' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m0,
        SUM(CASE WHEN ac.month_amortization = 'M+1' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m1,
        SUM(CASE WHEN ac.month_amortization = 'M+2' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m2,
        SUM(CASE WHEN ac.month_amortization = 'M+3' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m3,
        SUM(CASE WHEN ac.month_amortization = 'M+4' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m4,
        SUM(CASE WHEN ac.month_amortization = 'M+5' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m5,
        SUM(CASE WHEN ac.month_amortization = 'M+6' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m6,
        SUM(CASE WHEN ac.month_amortization = 'M+7' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m7,
        SUM(CASE WHEN ac.month_amortization = 'M+8' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m8,
        SUM(CASE WHEN ac.month_amortization = 'M+9' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m9,
        SUM(CASE WHEN ac.month_amortization = 'M+10' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m10,
        SUM(CASE WHEN ac.month_amortization = 'M+11' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m11,
        SUM(CASE WHEN ac.month_amortization = 'M+12' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m12,
        SUM(CASE WHEN ac.month_amortization = 'M+0' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m0,
        SUM(CASE WHEN ac.month_amortization = 'M+1' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m1,
        SUM(CASE WHEN ac.month_amortization = 'M+2' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m2,
        SUM(CASE WHEN ac.month_amortization = 'M+3' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m3,
        SUM(CASE WHEN ac.month_amortization = 'M+4' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m4,
        SUM(CASE WHEN ac.month_amortization = 'M+5' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m5,
        SUM(CASE WHEN ac.month_amortization = 'M+6' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m6,
        SUM(CASE WHEN ac.month_amortization = 'M+7' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m7,
        SUM(CASE WHEN ac.month_amortization = 'M+8' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m8,
        SUM(CASE WHEN ac.month_amortization = 'M+9' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m9,
        SUM(CASE WHEN ac.month_amortization = 'M+10' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m10,
        SUM(CASE WHEN ac.month_amortization = 'M+11' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m11,
        SUM(CASE WHEN ac.month_amortization = 'M+12' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m12
    FROM
        marketing_costs AS mc
    LEFT JOIN
        datalake_gsheets_clean.unit_economics_amortization_curve AS ac
            ON LOWER(mc.classification) = TRIM('amortização ' FROM ac.classification)
    WHERE
        (mc.dt_month_start BETWEEN ac.dt_term_start AND ac.dt_term_end)
        AND business = 'sale'
    GROUP BY 1,2
    ORDER BY 1,2
), supply_per_month_amortization AS (
SELECT
    dt_month_start,
    city_group,
    cost_amortized_m0 AS m0_supply_cost,
    COALESCE((LAG(cost_amortized_m1,1) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m1_supply_cost,
    COALESCE((LAG(cost_amortized_m2,2) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m2_supply_cost,
    COALESCE((LAG(cost_amortized_m3,3) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m3_supply_cost,
    COALESCE((LAG(cost_amortized_m4,4) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m4_supply_cost,
    COALESCE((LAG(cost_amortized_m5,5) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m5_supply_cost,
    COALESCE((LAG(cost_amortized_m6,6) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m6_supply_cost,
    COALESCE((LAG(cost_amortized_m7,7) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m7_supply_cost,
    COALESCE((LAG(cost_amortized_m8,8) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m8_supply_cost,
    COALESCE((LAG(cost_amortized_m9,9) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m9_supply_cost,
    COALESCE((LAG(cost_amortized_m10,10) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m10_supply_cost,
    COALESCE((LAG(cost_amortized_m11,11) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m11_supply_cost,
    COALESCE((LAG(cost_amortized_m12,12) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m12_supply_cost,
    budget_amortized_m0 AS m0_supply_budget,
    COALESCE((LAG(budget_amortized_m1,1) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m1_supply_budget,
    COALESCE((LAG(budget_amortized_m2,2) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m2_supply_budget,
    COALESCE((LAG(budget_amortized_m3,3) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m3_supply_budget,
    COALESCE((LAG(budget_amortized_m4,4) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m4_supply_budget,
    COALESCE((LAG(budget_amortized_m5,5) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m5_supply_budget,
    COALESCE((LAG(budget_amortized_m6,6) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m6_supply_budget,
    COALESCE((LAG(budget_amortized_m7,7) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m7_supply_budget,
    COALESCE((LAG(budget_amortized_m8,8) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m8_supply_budget,
    COALESCE((LAG(budget_amortized_m9,9) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m9_supply_budget,
    COALESCE((LAG(budget_amortized_m10,10) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m10_supply_budget,
    COALESCE((LAG(budget_amortized_m11,11) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m11_supply_budget,
    COALESCE((LAG(budget_amortized_m12,12) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m12_supply_budget
FROM
    supply_metric_amortization
), supply_amortized AS (
    SELECT
        dt_month_start,
        city_group,
        (m0_supply_cost + m1_supply_cost + m2_supply_cost + m3_supply_cost + m4_supply_cost + m5_supply_cost + m6_supply_cost + m7_supply_cost + m8_supply_cost + m9_supply_cost + m10_supply_cost + m11_supply_cost + m12_supply_cost) AS amortized_supply_cost,
        (m0_supply_budget + m1_supply_budget + m2_supply_budget + m3_supply_budget + m4_supply_budget + m5_supply_budget + m6_supply_budget + m7_supply_budget + m8_supply_budget + m9_supply_budget + m10_supply_budget + m11_supply_budget + m12_supply_budget) AS amortized_supply_budget
    FROM
        supply_per_month_amortization
), demand_metric_amortization AS (
    SELECT
        mc.dt_month_start,
        mc.city_group,
        SUM(CASE WHEN ac.month_amortization = 'M+0' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m0,
        SUM(CASE WHEN ac.month_amortization = 'M+1' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m1,
        SUM(CASE WHEN ac.month_amortization = 'M+2' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m2,
        SUM(CASE WHEN ac.month_amortization = 'M+3' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m3,
        SUM(CASE WHEN ac.month_amortization = 'M+4' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m4,
        SUM(CASE WHEN ac.month_amortization = 'M+5' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m5,
        SUM(CASE WHEN ac.month_amortization = 'M+6' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m6,
        SUM(CASE WHEN ac.month_amortization = 'M+7' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m7,
        SUM(CASE WHEN ac.month_amortization = 'M+8' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m8,
        SUM(CASE WHEN ac.month_amortization = 'M+9' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m9,
        SUM(CASE WHEN ac.month_amortization = 'M+10' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m10,
        SUM(CASE WHEN ac.month_amortization = 'M+11' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m11,
        SUM(CASE WHEN ac.month_amortization = 'M+12' THEN (ac.metric_amortization * mc.demand_cost) ELSE 0 END) AS cost_amortized_m12,
        SUM(CASE WHEN ac.month_amortization = 'M+0' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m0,
        SUM(CASE WHEN ac.month_amortization = 'M+1' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m1,
        SUM(CASE WHEN ac.month_amortization = 'M+2' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m2,
        SUM(CASE WHEN ac.month_amortization = 'M+3' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m3,
        SUM(CASE WHEN ac.month_amortization = 'M+4' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m4,
        SUM(CASE WHEN ac.month_amortization = 'M+5' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m5,
        SUM(CASE WHEN ac.month_amortization = 'M+6' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m6,
        SUM(CASE WHEN ac.month_amortization = 'M+7' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m7,
        SUM(CASE WHEN ac.month_amortization = 'M+8' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m8,
        SUM(CASE WHEN ac.month_amortization = 'M+9' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m9,
        SUM(CASE WHEN ac.month_amortization = 'M+10' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m10,
        SUM(CASE WHEN ac.month_amortization = 'M+11' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m11,
        SUM(CASE WHEN ac.month_amortization = 'M+12' THEN (ac.metric_amortization * mc.demand_budget) ELSE 0 END) AS budget_amortized_m12
    FROM
        marketing_costs AS mc
    LEFT JOIN
        datalake_gsheets_clean.unit_economics_amortization_curve AS ac
            ON LOWER(mc.classification) = TRIM('amortização ' FROM ac.classification)
    WHERE
        (mc.dt_month_start BETWEEN ac.dt_term_start AND ac.dt_term_end)
        AND business = 'sale'
    GROUP BY 1,2
    ORDER BY 1,2
), demand_per_month_amortization AS (
SELECT
    dt_month_start,
    city_group,
    cost_amortized_m0 AS m0_demand_cost,
    COALESCE((LAG(cost_amortized_m1,1) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m1_demand_cost,
    COALESCE((LAG(cost_amortized_m2,2) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m2_demand_cost,
    COALESCE((LAG(cost_amortized_m3,3) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m3_demand_cost,
    COALESCE((LAG(cost_amortized_m4,4) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m4_demand_cost,
    COALESCE((LAG(cost_amortized_m5,5) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m5_demand_cost,
    COALESCE((LAG(cost_amortized_m6,6) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m6_demand_cost,
    COALESCE((LAG(cost_amortized_m7,7) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m7_demand_cost,
    COALESCE((LAG(cost_amortized_m8,8) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m8_demand_cost,
    COALESCE((LAG(cost_amortized_m9,9) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m9_demand_cost,
    COALESCE((LAG(cost_amortized_m10,10) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m10_demand_cost,
    COALESCE((LAG(cost_amortized_m11,11) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m11_demand_cost,
    COALESCE((LAG(cost_amortized_m12,12) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m12_demand_cost,
    budget_amortized_m0 AS m0_demand_budget,
    COALESCE((LAG(budget_amortized_m1,1) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m1_demand_budget,
    COALESCE((LAG(budget_amortized_m2,2) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m2_demand_budget,
    COALESCE((LAG(budget_amortized_m3,3) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m3_demand_budget,
    COALESCE((LAG(budget_amortized_m4,4) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m4_demand_budget,
    COALESCE((LAG(budget_amortized_m5,5) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m5_demand_budget,
    COALESCE((LAG(budget_amortized_m6,6) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m6_demand_budget,
    COALESCE((LAG(budget_amortized_m7,7) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m7_demand_budget,
    COALESCE((LAG(budget_amortized_m8,8) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m8_demand_budget,
    COALESCE((LAG(budget_amortized_m9,9) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m9_demand_budget,
    COALESCE((LAG(budget_amortized_m10,10) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m10_demand_budget,
    COALESCE((LAG(budget_amortized_m11,11) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m11_demand_budget,
    COALESCE((LAG(budget_amortized_m12,12) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m12_demand_budget
FROM
    demand_metric_amortization
), demand_amortized AS (
    SELECT
        dt_month_start,
        city_group,
        (m0_demand_cost + m1_demand_cost + m2_demand_cost + m3_demand_cost + m4_demand_cost + m5_demand_cost + m6_demand_cost + m7_demand_cost + m8_demand_cost + m9_demand_cost + m10_demand_cost + m11_demand_cost + m12_demand_cost) AS amortized_demand_cost,
        (m0_demand_budget + m1_demand_budget + m2_demand_budget + m3_demand_budget + m4_demand_budget + m5_demand_budget + m6_demand_budget + m7_demand_budget + m8_demand_budget + m9_demand_budget + m10_demand_budget + m11_demand_budget + m12_demand_budget) AS amortized_demand_budget
    FROM
        demand_per_month_amortization
), branding_cost AS (
    SELECT
        dt_month_start,
        branding_cost,
        branding_budget
    FROM
        marketing_costs
    WHERE
        city_group = 'Brasil'
), total_sales AS (
    SELECT
        COALESCE(gv.dt_ccv, st.month_start) AS dt_month_start,
        SUM(gv.potential_closed_deals) AS potential_closed_deals,
        SUM(st.potential_closed_deals_target) AS potential_closed_deals_target
    FROM
        grouped_sale_volumes AS gv
    LEFT JOIN
        sale_targets AS st
            ON gv.dt_ccv = st.month_start
    GROUP BY 1
), branding_base_brasil AS (
    SELECT
        COALESCE(bc.dt_month_start, ts.dt_month_start) AS dt_month_start,
        bc.branding_cost,
        bc.branding_budget,
        ts.potential_closed_deals,
        ts.potential_closed_deals_target
    FROM
        branding_cost AS bc
    FULL OUTER JOIN
        total_sales AS ts
            ON bc.dt_month_start = ts.dt_month_start
), branding_demand_supply_base AS (
    SELECT
        mc.dt_month_start,
        mc.city_group,
        SUM(potential_closed_deals) AS potential_closed_deals,
        SUM(potential_closed_deals_target) AS potential_closed_deals_target,
        SUM(branding_cost) AS branding_cost,
        SUM(branding_budget) AS branding_budget
    FROM
        marketing_costs AS mc
    LEFT JOIN
        grouped_sale_volumes AS gr
            ON mc.dt_month_start = gr.dt_ccv AND mc.city_group = gr.city_group
    LEFT JOIN
        sale_targets AS st
            ON mc.dt_month_start = st.month_start
            AND mc.city_group = st.city_group
    WHERE
        mc.classification = 'Branded'
    GROUP BY 1,2
), branding_demand_supply_share AS (
    SELECT
        bd.dt_month_start,
        bd.city_group,
        ((bd.branding_cost+COALESCE(bb.branding_cost, 0)*bd.potential_closed_deals/bb.potential_closed_deals)*0.5) AS branding_demand_supply_share,
        ((bd.branding_budget+COALESCE(bb.branding_budget, 0)*bd.potential_closed_deals_target/bb.potential_closed_deals_target)*0.5) AS branding_demand_supply_budget
    FROM
        branding_demand_supply_base AS bd
    LEFT JOIN
        branding_base_brasil AS bb
            ON bd.dt_month_start = bb.dt_month_start
), branding_demand_metric AS (
    SELECT
        bs.dt_month_start,
        bs.city_group,
        SUM(CASE WHEN ac.month_amortization = 'M+0' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m0,
        SUM(CASE WHEN ac.month_amortization = 'M+1' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m1,
        SUM(CASE WHEN ac.month_amortization = 'M+2' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m2,
        SUM(CASE WHEN ac.month_amortization = 'M+3' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m3,
        SUM(CASE WHEN ac.month_amortization = 'M+4' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m4,
        SUM(CASE WHEN ac.month_amortization = 'M+5' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m5,
        SUM(CASE WHEN ac.month_amortization = 'M+6' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m6,
        SUM(CASE WHEN ac.month_amortization = 'M+7' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m7,
        SUM(CASE WHEN ac.month_amortization = 'M+8' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m8,
        SUM(CASE WHEN ac.month_amortization = 'M+9' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m9,
        SUM(CASE WHEN ac.month_amortization = 'M+10' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m10,
        SUM(CASE WHEN ac.month_amortization = 'M+11' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m11,
        SUM(CASE WHEN ac.month_amortization = 'M+12' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m12,
        SUM(CASE WHEN ac.month_amortization = 'M+0' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m0,
        SUM(CASE WHEN ac.month_amortization = 'M+1' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m1,
        SUM(CASE WHEN ac.month_amortization = 'M+2' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m2,
        SUM(CASE WHEN ac.month_amortization = 'M+3' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m3,
        SUM(CASE WHEN ac.month_amortization = 'M+4' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m4,
        SUM(CASE WHEN ac.month_amortization = 'M+5' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m5,
        SUM(CASE WHEN ac.month_amortization = 'M+6' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m6,
        SUM(CASE WHEN ac.month_amortization = 'M+7' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m7,
        SUM(CASE WHEN ac.month_amortization = 'M+8' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m8,
        SUM(CASE WHEN ac.month_amortization = 'M+9' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m9,
        SUM(CASE WHEN ac.month_amortization = 'M+10' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m10,
        SUM(CASE WHEN ac.month_amortization = 'M+11' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m11,
        SUM(CASE WHEN ac.month_amortization = 'M+12' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m12
    FROM
        branding_demand_supply_share AS bs
    LEFT JOIN
        datalake_gsheets_clean.unit_economics_amortization_curve AS ac
            ON TRIM('amortização ' FROM ac.classification) = 'demand'
    WHERE
        (bs.dt_month_start BETWEEN ac.dt_term_start AND ac.dt_term_end)
        AND ac.business = 'sale'
    GROUP BY 1,2
    ORDER BY 1,2
), branding_demand_per_month AS (
SELECT
    dt_month_start,
    city_group,
    cost_amortized_m0 AS m0_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m1,1) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m1_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m2,2) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m2_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m3,3) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m3_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m4,4) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m4_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m5,5) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m5_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m6,6) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m6_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m7,7) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m7_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m8,8) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m8_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m9,9) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m9_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m10,10) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m10_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m11,11) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m11_branding_demand_cost,
    COALESCE((LAG(cost_amortized_m12,12) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m12_branding_demand_cost,
    budget_amortized_m0 AS m0_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m1,1) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m1_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m2,2) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m2_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m3,3) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m3_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m4,4) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m4_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m5,5) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m5_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m6,6) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m6_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m7,7) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m7_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m8,8) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m8_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m9,9) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m9_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m10,10) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m10_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m11,11) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m11_branding_demand_budget,
    COALESCE((LAG(budget_amortized_m12,12) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m12_branding_demand_budget
FROM
    branding_demand_metric
), amortized_branding_demand_share AS (
    SELECT
        dt_month_start,
        city_group,
        (m0_branding_demand_cost + m1_branding_demand_cost + m2_branding_demand_cost + m3_branding_demand_cost + m4_branding_demand_cost + m5_branding_demand_cost + m6_branding_demand_cost + m7_branding_demand_cost + m8_branding_demand_cost + m9_branding_demand_cost + m10_branding_demand_cost + m11_branding_demand_cost + m12_branding_demand_cost) AS amortized_branding_demand_share,
        (m0_branding_demand_budget + m1_branding_demand_budget + m2_branding_demand_budget + m3_branding_demand_budget + m4_branding_demand_budget + m5_branding_demand_budget + m6_branding_demand_budget + m7_branding_demand_budget + m8_branding_demand_budget + m9_branding_demand_budget + m10_branding_demand_budget + m11_branding_demand_budget + m12_branding_demand_budget) AS amortized_branding_demand_budget
    FROM
        branding_demand_per_month
), branding_supply_metric AS (
    SELECT
        bs.dt_month_start,
        bs.city_group,
        SUM(CASE WHEN ac.month_amortization = 'M+0' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m0,
        SUM(CASE WHEN ac.month_amortization = 'M+1' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m1,
        SUM(CASE WHEN ac.month_amortization = 'M+2' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m2,
        SUM(CASE WHEN ac.month_amortization = 'M+3' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m3,
        SUM(CASE WHEN ac.month_amortization = 'M+4' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m4,
        SUM(CASE WHEN ac.month_amortization = 'M+5' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m5,
        SUM(CASE WHEN ac.month_amortization = 'M+6' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m6,
        SUM(CASE WHEN ac.month_amortization = 'M+7' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m7,
        SUM(CASE WHEN ac.month_amortization = 'M+8' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m8,
        SUM(CASE WHEN ac.month_amortization = 'M+9' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m9,
        SUM(CASE WHEN ac.month_amortization = 'M+10' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m10,
        SUM(CASE WHEN ac.month_amortization = 'M+11' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m11,
        SUM(CASE WHEN ac.month_amortization = 'M+12' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m12,
        SUM(CASE WHEN ac.month_amortization = 'M+0' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m0,
        SUM(CASE WHEN ac.month_amortization = 'M+1' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m1,
        SUM(CASE WHEN ac.month_amortization = 'M+2' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m2,
        SUM(CASE WHEN ac.month_amortization = 'M+3' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m3,
        SUM(CASE WHEN ac.month_amortization = 'M+4' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m4,
        SUM(CASE WHEN ac.month_amortization = 'M+5' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m5,
        SUM(CASE WHEN ac.month_amortization = 'M+6' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m6,
        SUM(CASE WHEN ac.month_amortization = 'M+7' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m7,
        SUM(CASE WHEN ac.month_amortization = 'M+8' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m8,
        SUM(CASE WHEN ac.month_amortization = 'M+9' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m9,
        SUM(CASE WHEN ac.month_amortization = 'M+10' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m10,
        SUM(CASE WHEN ac.month_amortization = 'M+11' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m11,
        SUM(CASE WHEN ac.month_amortization = 'M+12' THEN (ac.metric_amortization * bs.branding_demand_supply_budget) ELSE 0 END) AS budget_amortized_m12
    FROM
        branding_demand_supply_share AS bs
    LEFT JOIN
        datalake_gsheets_clean.unit_economics_amortization_curve AS ac
            ON TRIM('amortização ' FROM ac.classification) = 'supply'
    WHERE
        (bs.dt_month_start BETWEEN ac.dt_term_start AND ac.dt_term_end)
        AND ac.business = 'sale'
    GROUP BY 1,2
    ORDER BY 1,2
), branding_supply_per_month AS (
SELECT
    dt_month_start,
    city_group,
    cost_amortized_m0 AS m0_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m1,1) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m1_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m2,2) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m2_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m3,3) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m3_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m4,4) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m4_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m5,5) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m5_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m6,6) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m6_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m7,7) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m7_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m8,8) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m8_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m9,9) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m9_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m10,10) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m10_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m11,11) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m11_branding_supply_cost,
    COALESCE((LAG(cost_amortized_m12,12) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m12_branding_supply_cost,
    budget_amortized_m0 AS m0_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m1,1) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m1_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m2,2) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m2_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m3,3) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m3_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m4,4) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m4_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m5,5) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m5_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m6,6) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m6_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m7,7) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m7_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m8,8) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m8_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m9,9) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m9_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m10,10) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m10_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m11,11) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m11_branding_supply_budget,
    COALESCE((LAG(budget_amortized_m12,12) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m12_branding_supply_budget
FROM
    branding_supply_metric
), amortized_branding_supply_share AS (
    SELECT
        dt_month_start,
        city_group,
        (m0_branding_supply_cost + m1_branding_supply_cost + m2_branding_supply_cost + m3_branding_supply_cost + m4_branding_supply_cost + m5_branding_supply_cost + m6_branding_supply_cost + m7_branding_supply_cost + m8_branding_supply_cost + m9_branding_supply_cost + m10_branding_supply_cost + m11_branding_supply_cost + m12_branding_supply_cost) AS amortized_branding_supply_share,
        (m0_branding_supply_budget + m1_branding_supply_budget + m2_branding_supply_budget + m3_branding_supply_budget + m4_branding_supply_budget + m5_branding_supply_budget + m6_branding_supply_budget + m7_branding_supply_budget + m8_branding_supply_budget + m9_branding_supply_budget + m10_branding_supply_budget + m11_branding_supply_budget + m12_branding_supply_budget) AS amortized_branding_supply_budget
    FROM
        branding_supply_per_month
)

SELECT
    COALESCE(sv.dt_ccv, st.month_start, mc.dt_month_start, sa.dt_month_start, da.dt_month_start, ab.dt_month_start, abd.dt_month_start) AS dt_month_start,
    TRIM(COALESCE(sv.city_group, st.city_group, mc.city_group, sa.city_group, da.city_group, ab.city_group, abd.city_group)) AS city_group,
    sv.ccv,
    sv.potential_closed_deals,
    sv.sale_price_agreed,
    CAST(st.ccv_target AS DECIMAL(38,18)) AS ccv_target,
    CAST(st.potential_closed_deals_target AS DECIMAL(38,18)) AS potential_closed_deals_target,
    mc.demand_cost,
    mc.supply_cost,
    mc.branding_cost,
    mc.demand_budget,
    mc.supply_budget,
    mc.branding_budget,
    sa.amortized_supply_cost,
    sa.amortized_supply_budget,
    da.amortized_demand_cost,
    da.amortized_demand_budget,
    ab.amortized_branding_supply_share,
    abd.amortized_branding_demand_share,
    ab.amortized_branding_supply_budget,
    abd.amortized_branding_demand_budget
FROM
    grouped_sale_volumes AS sv
FULL OUTER JOIN
    sale_targets AS st
        ON sv.dt_ccv = st.month_start
        AND sv.city_group = st.city_group
FULL OUTER JOIN
    marketing_costs_date_city AS mc
        ON sv.dt_ccv = mc.dt_month_start
        AND sv.city_group = mc.city_group
FULL OUTER JOIN
    supply_amortized AS sa
        ON sv.dt_ccv = sa.dt_month_start
        AND sv.city_group = sa.city_group
FULL OUTER JOIN
    demand_amortized AS da
        ON sv.dt_ccv = da.dt_month_start
        AND sv.city_group = da.city_group
FULL OUTER JOIN
    amortized_branding_supply_share AS ab
        ON sv.dt_ccv = ab.dt_month_start
        AND sv.city_group = ab.city_group
FULL OUTER JOIN
    amortized_branding_demand_share AS abd
        ON sv.dt_ccv = abd.dt_month_start
        AND sv.city_group = abd.city_group
