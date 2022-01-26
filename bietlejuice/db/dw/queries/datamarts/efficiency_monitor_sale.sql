WITH sale_volumes AS (
    select 
        coalesce(oh.id_offer,fo.sk_offer) as sk_offer,
        oh.executive_lead,
        oh.status,
        coalesce(fo.sk_house, h.id_house_quintoandar::bigint) as sk_house,
        coalesce(fo.sk_buyer,oh.id_client_cm, oh.id_user_5a) as sk_buyer,
        case 
            when oh.offer_flow like '%HUB%' then 'HUB'
            when oh.offer_flow = 'CENTRAL' then 'CENTRAL'
            else 'DealMaking'
        end as offer_flow,
        case 
            when executive_lead = 'Leonardo Monteiro' or oh.offer_flow = 'HUB_BV_V0' then 'HUB Bela Vista'
            when executive_lead = 'Rodrigo Pereira' or oh.offer_flow = 'HUB_VM_V0' then 'HUB Vila Mariana' 
            when oh.offer_flow = 'CENTRAL' AND dr.city_group = 'Porto Alegre' then 'CENTRAL POA'
            when oh.offer_flow = 'CENTRAL' AND dr.city_group = 'RMSP' then 'CENTRAL SP'
            when oh.offer_flow = 'CENTRAL' AND dr.city_group = 'Rio de Janeiro' then 'CENTRAL RJ'
            else 'DealMaking'
        end as offer_flow_detail,
        city_group,
        coalesce(to_date(fo.sk_offer_submitted_date, 'YYYYMMDD'), oh.dt_offer_submitted) as dt_offer,
        coalesce(oh.dt_sale_agreement_signed, to_date(nullif(fo.sk_sale_agreement_signed_date,-1), 'YYYYMMDD')) as dt_ccv_signed,
        date_diff('day', dt_offer, dt_ccv_signed) as days_offer_submitted_to_sale_agreement_signed,
        coalesce(dsa.sale_price_agreed, oh.sale_price_agreed) as sale_price_agreed
    from sale.fact_offers fo 
    LEFT JOIN sale.dim_sale_agreement dsa on dsa.sk_offer = fo.sk_offer
    full outer join datalake_gsheets_clean_prod.offers_hub_central oh 
        on fo.sk_offer = oh.id_offer
    left join datalake_casa_mineira_crm_clean_prod.house h
            on h.id = oh.id_house_cm
    left join sale.fact_listings fl 
        on fl.sk_house = coalesce(fo.sk_house, h.id_house_quintoandar::bigint)
    left join dim_region dr 
        on dr.sk_region = fl.sk_region
), grouped_sale_volumes AS (
    select 
        date_trunc('month',dt_ccv_signed) as dt_ccv,
        city_group,
        count(distinct sk_offer) AS ccv,
        ROUND(count(distinct sk_offer) * 0.7960, 0) AS potential_closed_deals,
        avg(sale_price_agreed) as sale_price_agreed
    from sale_volumes
    where dt_ccv >= '2020-01-01' AND city_group IS NOT NULL AND city_group <> 'Not Mapped'
    group by 1, 2
), base_act AS (
    SELECT
        DATE(dt_cost) AS dt_cost,
        city_group,
        planning_mkt_level1,
        planning_mkt_level2,
        planning_mkt_level3,
        SUM(costs) AS costs
    FROM datamarts.marketing_demand_supply_branding_costs
    WHERE 
        dt_cost BETWEEN '2020-01-01' AND date_trunc('week',CURRENT_DATE)
        AND business = 'Sale'
    GROUP BY 1,2,3,4,5
), base_tgt AS (
    SELECT
        DATE(date) AS dt_cost,
        city_group,
        planning_mkt_level1,
        planning_mkt_level2,
        planning_mkt_level3,
        SUM(budget__mensal) AS budget_mensal
    FROM datalake_raw.gsheets_costs_targets
    WHERE date BETWEEN '2020-07-01' AND date_trunc('week',CURRENT_DATE)
        AND business = 'Sale'
    GROUP BY 1,2,3,4,5
), base_costs AS (
    SELECT
        COALESCE(a.dt_cost, t.dt_cost) AS dt_reference,
        COALESCE(a.city_group,t.city_group) AS city_group,
        COALESCE(a.planning_mkt_level1, t.planning_mkt_level1) AS planning_mkt_level1,
        COALESCE(a.planning_mkt_level2,t.planning_mkt_level2) AS planning_mkt_level2,
        COALESCE(a.planning_mkt_level3,t.planning_mkt_level3) AS planning_mkt_level3,
        SUM(a.costs) AS cost_act,
        SUM(t.budget_mensal) AS budget_mensal
    FROM base_act AS a
     FULL OUTER JOIN base_tgt AS t 
        ON a.dt_cost = t.dt_cost
        AND a.city_group=t.city_group
        AND a.planning_mkt_level1=t.planning_mkt_level1
        AND a.planning_mkt_level2=t.planning_mkt_level2
        AND a.planning_mkt_level3=t.planning_mkt_level3
    GROUP BY 1,2,3,4,5
), marketing_costs AS (
    SELECT
        date_trunc('month',dt_reference) as dt_month_start,
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
  WHERE dt_reference < date_trunc('week',CURRENT_DATE)  
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
    FROM marketing_costs
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
    FROM marketing_costs AS mc
    LEFT JOIN datalake_gsheets_clean_prod.unit_economics_amortization_curve AS ac
        ON LOWER(mc.classification) = TRIM('amortização ' FROM ac.classification)
    WHERE (mc.dt_month_start BETWEEN ac.dt_term_start AND ac.dt_term_end) AND business = 'sale'
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
    FROM supply_per_month_amortization
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
    FROM marketing_costs AS mc
    LEFT JOIN datalake_gsheets_clean_prod.unit_economics_amortization_curve AS ac
        ON LOWER(mc.classification) = TRIM('amortização ' FROM ac.classification)
    WHERE (mc.dt_month_start BETWEEN ac.dt_term_start AND ac.dt_term_end) AND business = 'sale'
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
    FROM demand_per_month_amortization
), branding_cost AS (
    SELECT
        dt_month_start,
        branding_cost
    FROM marketing_costs
    WHERE city_group = 'Brasil'
), total_rentals AS (
    SELECT
        dt_ccv AS dt_month_start,
        SUM(potential_closed_deals) AS potential_closed_deals
    FROM
        grouped_sale_volumes
    GROUP BY 1
), branding_base_brasil AS (
    SELECT
        COALESCE(bc.dt_month_start, tr.dt_month_start) AS dt_month_start,
        bc.branding_cost,
        tr.potential_closed_deals
    FROM branding_cost AS bc
    FULL OUTER JOIN
        total_rentals AS tr
        ON bc.dt_month_start = tr.dt_month_start
), branding_demand_supply_base AS (
    SELECT
        mc.dt_month_start,
        mc.city_group,
        SUM(potential_closed_deals) AS potential_closed_deals,
        SUM(branding_cost) AS branding_cost
    FROM
        marketing_costs AS mc
    LEFT JOIN
        grouped_sale_volumes AS gr
        ON mc.dt_month_start = gr.dt_ccv AND mc.city_group = gr.city_group
    WHERE mc.classification = 'Branded'
    GROUP BY 1,2
), branding_demand_supply_share AS (
    SELECT
        bd.dt_month_start,
        bd.city_group,
        ((bd.branding_cost+bb.branding_cost*bd.potential_closed_deals/bb.potential_closed_deals)*0.5) AS branding_demand_supply_share
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
        SUM(CASE WHEN ac.month_amortization = 'M+12' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m12
    FROM branding_demand_supply_share AS bs
    LEFT JOIN datalake_gsheets_clean_prod.unit_economics_amortization_curve AS ac
        ON TRIM('amortização ' FROM ac.classification) = 'demand'
    WHERE (bs.dt_month_start BETWEEN ac.dt_term_start AND ac.dt_term_end) AND ac.business = 'sale'
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
    COALESCE((LAG(cost_amortized_m12,12) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m12_branding_demand_cost
FROM
    branding_demand_metric
), amortized_branding_demand_share AS (
    SELECT
        dt_month_start,
        city_group,
        (m0_branding_demand_cost + m1_branding_demand_cost + m2_branding_demand_cost + m3_branding_demand_cost + m4_branding_demand_cost + m5_branding_demand_cost + m6_branding_demand_cost + m7_branding_demand_cost + m8_branding_demand_cost + m9_branding_demand_cost + m10_branding_demand_cost + m11_branding_demand_cost + m12_branding_demand_cost) AS amortized_branding_demand_share
    FROM branding_demand_per_month
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
        SUM(CASE WHEN ac.month_amortization = 'M+12' THEN (ac.metric_amortization * bs.branding_demand_supply_share) ELSE 0 END) AS cost_amortized_m12
    FROM branding_demand_supply_share AS bs
    LEFT JOIN datalake_gsheets_clean_prod.unit_economics_amortization_curve AS ac
        ON TRIM('amortização ' FROM ac.classification) = 'supply'
    WHERE (bs.dt_month_start BETWEEN ac.dt_term_start AND ac.dt_term_end) AND ac.business = 'sale'
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
    COALESCE((LAG(cost_amortized_m12,12) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m12_branding_supply_cost
FROM
    branding_supply_metric
), amortized_branding_supply_share AS (
    SELECT
        dt_month_start,
        city_group,
        (m0_branding_supply_cost + m1_branding_supply_cost + m2_branding_supply_cost + m3_branding_supply_cost + m4_branding_supply_cost + m5_branding_supply_cost + m6_branding_supply_cost + m7_branding_supply_cost + m8_branding_supply_cost + m9_branding_supply_cost + m10_branding_supply_cost + m11_branding_supply_cost + m12_branding_supply_cost) AS amortized_branding_supply_share
    FROM branding_supply_per_month
)
SELECT
    COALESCE(sv.dt_ccv, mc.dt_month_start, sa.dt_month_start, da.dt_month_start, ab.dt_month_start, abd.dt_month_start) AS dt_month_start,
    COALESCE(sv.city_group, mc.city_group, sa.city_group, da.city_group, ab.city_group, abd.city_group) AS city_group,
    sv.potential_closed_deals,
    sv.sale_price_agreed,
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
    abd.amortized_branding_demand_share
FROM grouped_sale_volumes AS sv
FULL OUTER JOIN marketing_costs_date_city AS mc
    ON sv.dt_ccv = mc.dt_month_start AND sv.city_group = mc.city_group
FULL OUTER JOIN supply_amortized AS sa
    ON sv.dt_ccv = sa.dt_month_start AND sv.city_group = sa.city_group
FULL OUTER JOIN demand_amortized AS da
    ON sv.dt_ccv = da.dt_month_start AND sv.city_group = da.city_group
FULL OUTER JOIN amortized_branding_supply_share AS ab
    ON sv.dt_ccv = ab.dt_month_start AND sv.city_group = ab.city_group
FULL OUTER JOIN amortized_branding_demand_share AS abd
    ON sv.dt_ccv = abd.dt_month_start AND sv.city_group = abd.city_group