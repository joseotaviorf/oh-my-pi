WITH
rentals_and_tickets AS (
    SELECT
        CAST(COALESCE(dc.dt_start, dc.dt_entrance) AS DATE) AS dt_reference,
        dr.city_group,
        RANK() OVER(PARTITION BY SUBSTRING(sk_house_listing,1,9) ORDER BY hl.sk_house_listing) AS n_order_c,
        hl.sk_house_listing,
        dc.sk_contract,
        dc.rent
    FROM dim_contract AS dc
    LEFT JOIN fact_house_listings AS hl
        ON dc.sk_contract = hl.sk_contract
    LEFT JOIN dim_region AS dr
        ON hl.sk_region = dr.sk_region  
    WHERE dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active and ended
        AND DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
        AND (DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < dc.dt_annulment OR dc.dt_annulment IS NULL)
), grouped_rentals_and_tickets AS (
    SELECT 
    	DATE(date_trunc('month',dt_reference)) as dt_month_start, 
    	city_group,
    	COUNT(DISTINCT sk_contract) AS new_rentals,
    	COUNT(DISTINCT CASE WHEN n_order_c = 1 THEN sk_contract END) AS new_first_rentals,
    	SUM(rent) AS total_ticket_new_rentals,
    	SUM(CASE WHEN n_order_c = 1 THEN rent END) AS total_ticket_new_first_rentals
    FROM rentals_and_tickets
    WHERE dt_reference >= '2020-01-01' AND city_group IS NOT NULL
    GROUP BY 1, 2
), base_act AS (
    SELECT 
        CAST(dt_cost AS DATE) AS dt_reference, 
        city_group,
        planning_mkt_level1,
        CASE WHEN planning_mkt_level2 = 'Organic' THEN 'Branded' ELSE planning_mkt_level2 END AS planning_mkt_level2,
        planning_mkt_level3,
        SUM(costs) AS cost_act
    FROM datamarts.marketing_demand_supply_branding_costs
    WHERE 
        business = 'Rental'
        AND dt_cost BETWEEN DATE('2020-01-01') AND LAST_DAY(CURRENT_DATE)
    GROUP by 1,2,3,4,5
), base_tgt as(
    SELECT 
        CAST("date" AS DATE) AS dt_reference,
        city_group,
        planning_mkt_level1,
        CASE WHEN planning_mkt_level2 = 'Organic' THEN 'Branded' ELSE planning_mkt_level2 END AS planning_mkt_level2,
        planning_mkt_level3,
        SUM(budget__quarter) AS cost_budget_quarter,
        SUM(budget__mensal) AS cost_budget_mensal
    FROM datalake_raw.gsheets_costs_targets 
    WHERE 
        business = 'Rental'
        AND date BETWEEN date('2020-01-01') AND LAST_DAY(CURRENT_DATE)
    GROUP BY 1,2,3,4,5
), base_costs AS (
    SELECT
        COALESCE(a.dt_reference, t.dt_reference) AS dt_reference,
        COALESCE(a.city_group,t.city_group) AS city_group,
        COALESCE(a.planning_mkt_level1, t.planning_mkt_level1) AS planning_mkt_level1,
        NULL AS "model",
        COALESCE(a.planning_mkt_level2,t.planning_mkt_level2) AS planning_mkt_level2,
        CASE
            WHEN COALESCE(a.planning_mkt_level3,t.planning_mkt_level3) = 'PWA - Paid' THEN 'Paid'
            WHEN COALESCE(a.planning_mkt_level3,t.planning_mkt_level3) = 'Not Mapped' THEN 'Other'
            WHEN COALESCE(a.planning_mkt_level3,t.planning_mkt_level3) = 'Autonomuos Agent' THEN 'CR'
            WHEN COALESCE(a.planning_mkt_level3,t.planning_mkt_level3) = 'CIQ' THEN 'CR'
            ELSE COALESCE(a.planning_mkt_level3,t.planning_mkt_level3)
        END AS planning_mkt_level3,
        SUM(a.cost_act) AS cost_act,
        SUM(t.cost_budget_quarter) AS cost_budget_quarter,
        SUM(t.cost_budget_mensal) AS cost_budget_mensal
    FROM base_act AS a
     FULL OUTER JOIN base_tgt AS t 
        ON a.dt_reference = t.dt_reference
        AND a.city_group=t.city_group
        AND a.planning_mkt_level1=t.planning_mkt_level1
        AND a.planning_mkt_level2=t.planning_mkt_level2
        AND a.planning_mkt_level3=t.planning_mkt_level3
    GROUP BY 1,2,3,4,5,6
), marketing_costs AS (
    SELECT
        date_trunc('month',dt_reference) as dt_month_start,
        city_group,
        planning_mkt_level1 AS classification,
        SUM(CASE WHEN planning_mkt_level1 = 'Demand' THEN cost_act ELSE 0 END) AS demand_cost,
        SUM(CASE WHEN planning_mkt_level1 = 'Supply' AND planning_mkt_level3 != 'CR' THEN cost_act ELSE 0 END) AS supply_cost,
        SUM(CASE WHEN planning_mkt_level1 = 'Branded' THEN cost_act ELSE 0 END) AS branding_cost,
        SUM(CASE WHEN planning_mkt_level1 = 'Demand' THEN cost_budget_mensal ELSE 0 END) AS demand_budget,
        SUM(CASE WHEN planning_mkt_level1 = 'Supply' AND planning_mkt_level3 != 'CR' THEN cost_budget_mensal ELSE 0 END) AS supply_budget,
        SUM(CASE WHEN planning_mkt_level1 = 'Branded' THEN cost_budget_mensal ELSE 0 END) AS branding_budget
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
), supply_metric_amortization AS (
    SELECT
        mc.dt_month_start,
        mc.city_group,
        SUM(CASE WHEN ac.month_amortization = 'M+0' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m0,
        SUM(CASE WHEN ac.month_amortization = 'M+1' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m1,
        SUM(CASE WHEN ac.month_amortization = 'M+2' THEN (ac.metric_amortization * mc.supply_cost) ELSE 0 END) AS cost_amortized_m2,
        SUM(CASE WHEN ac.month_amortization = 'M+0' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m0,
        SUM(CASE WHEN ac.month_amortization = 'M+1' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m1,
        SUM(CASE WHEN ac.month_amortization = 'M+2' THEN (ac.metric_amortization * mc.supply_budget) ELSE 0 END) AS budget_amortized_m2
    FROM marketing_costs AS mc
    LEFT JOIN datalake_gsheets_clean_prod.unit_economics_amortization_curve AS ac
    ON LOWER(mc.classification) = TRIM('amortização ' FROM ac.classification)
    WHERE (mc.dt_month_start BETWEEN ac.dt_term_start AND ac.dt_term_end) AND business = 'rental'
    GROUP BY 1,2
    ORDER BY 1,2
), supply_per_month_amortization AS (
SELECT
    dt_month_start,
    city_group,
    cost_amortized_m0 AS m0_supply_cost,
    COALESCE((LAG(cost_amortized_m1,1) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m1_supply_cost,
    COALESCE((LAG(cost_amortized_m2,2) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m2_supply_cost,
    budget_amortized_m0 AS m0_supply_budget,
    COALESCE((LAG(budget_amortized_m1,1) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m1_supply_budget,
    COALESCE((LAG(budget_amortized_m2,2) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m2_supply_budget
FROM
    supply_metric_amortization
), supply_amortized AS (
    SELECT
        dt_month_start,
        city_group,
        (m0_supply_cost + m1_supply_cost + m2_supply_cost) AS amortized_supply_cost,
        (m0_supply_budget + m1_supply_budget + m2_supply_budget) AS amortized_supply_budget
    FROM supply_per_month_amortization
), branding_amortized AS (
    SELECT
        dt_month_start,
        city_group,
        SUM(branding_cost/12) OVER (PARTITION BY city_group ORDER BY dt_month_start ROWS 11 PRECEDING) AS amortized_brand_cost,
        SUM(branding_budget/12) OVER (PARTITION BY city_group ORDER BY dt_month_start ROWS 11 PRECEDING) AS amortized_brand_budget
    FROM
        marketing_costs
    WHERE classification = 'Branded'
), amortized_cost AS (
    SELECT
        dt_month_start,
        amortized_brand_cost
    FROM branding_amortized
    WHERE city_group = 'Brasil'
), total_rentals AS (
    SELECT
        dt_month_start,
        SUM(new_rentals) AS new_rentals,
        SUM(new_first_rentals) AS new_first_rentals
    FROM
        grouped_rentals_and_tickets
    GROUP BY 1
), branding_base_brasil AS (
    SELECT
        COALESCE(ac.dt_month_start, tr.dt_month_start) AS dt_month_start,
        ac.amortized_brand_cost,
        tr.new_rentals,
        tr.new_first_rentals
    FROM amortized_cost AS ac
    FULL OUTER JOIN
        total_rentals AS tr
        ON ac.dt_month_start = tr.dt_month_start
), branding_demand_supply_base AS (
    SELECT
        ba.dt_month_start,
        ba.city_group,
        SUM(new_rentals) AS new_rentals,
        SUM(new_first_rentals) AS new_first_rentals,
        SUM(amortized_brand_cost) AS amortized_brand_cost
    FROM
        branding_amortized AS ba
    LEFT JOIN
        grouped_rentals_and_tickets AS gr
        ON ba.dt_month_start = gr.dt_month_start AND ba.city_group = gr.city_group
    GROUP BY 1,2
), branding_demand_amortized AS (
    SELECT
        bd.dt_month_start,
        bd.city_group,
        ((bd.amortized_brand_cost+bb.amortized_brand_cost*bd.new_rentals/bb.new_rentals)*0.5) AS amortized_brand_demand_cost
    FROM
        branding_demand_supply_base AS bd
    LEFT JOIN
        branding_base_brasil AS bb
        ON bd.dt_month_start = bb.dt_month_start
), branding_supply_amortized AS (
    SELECT
        bd.dt_month_start,
        bd.city_group,
        ((bd.amortized_brand_cost+bb.amortized_brand_cost*bd.new_first_rentals/bb.new_first_rentals)*0.5) AS amortized_brand_supply_cost
    FROM
        branding_demand_supply_base AS bd
    LEFT JOIN
        branding_base_brasil AS bb
        ON bd.dt_month_start = bb.dt_month_start
), brand_supply_metric_amortization_amortization AS (
    SELECT
        ba.dt_month_start,
        ba.city_group,
        SUM(CASE WHEN ac.month_amortization = 'M+0' THEN (ac.metric_amortization * ba.amortized_brand_supply_cost) ELSE 0 END) AS cost_amortized_m0,
        SUM(CASE WHEN ac.month_amortization = 'M+1' THEN (ac.metric_amortization * ba.amortized_brand_supply_cost) ELSE 0 END) AS cost_amortized_m1,
        SUM(CASE WHEN ac.month_amortization = 'M+2' THEN (ac.metric_amortization * ba.amortized_brand_supply_cost) ELSE 0 END) AS cost_amortized_m2
    FROM branding_supply_amortized AS ba
    LEFT JOIN datalake_gsheets_clean_prod.unit_economics_amortization_curve AS ac
    ON TRIM('amortização ' FROM ac.classification) = 'supply'
    WHERE (ba.dt_month_start BETWEEN ac.dt_term_start AND ac.dt_term_end) AND business = 'rental'
    GROUP BY 1,2
    ORDER BY 1,2
), brand_supply_per_month_amortization_amortization AS (
SELECT
    dt_month_start,
    city_group,
    cost_amortized_m0 AS m0_brand_supply_cost,
    COALESCE((LAG(cost_amortized_m1,1) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m1_brand_supply_cost,
    COALESCE((LAG(cost_amortized_m2,2) OVER(PARTITION BY city_group ORDER BY dt_month_start)), 0) AS m2_brand_supply_cost
FROM
    brand_supply_metric_amortization_amortization
), brand_supply_amortized_amortized AS (
    SELECT
        dt_month_start,
        city_group,
        (m0_brand_supply_cost + m1_brand_supply_cost + m2_brand_supply_cost) AS amortized_amortized_brand_supply_cost
    FROM brand_supply_per_month_amortization_amortization
)
SELECT
    COALESCE(rt.dt_month_start, mc.dt_month_start, sa.dt_month_start, br.dt_month_start, ba.dt_month_start, bd.dt_month_start, bs.dt_month_start) AS dt_month_start,
    COALESCE(rt.city_group, mc.city_group, sa.city_group, br.city_group, ba.city_group, bd.city_group, bs.city_group) AS city_group,
    rt.new_rentals,
    rt.new_first_rentals,
    rt.total_ticket_new_rentals,
    rt.total_ticket_new_first_rentals,
    mc.demand_cost,
    mc.supply_cost,
    mc.branding_cost,
    mc.demand_budget,
    mc.supply_budget,
    mc.branding_budget,
    sa.amortized_supply_cost,
    sa.amortized_supply_budget,
    br.amortized_brand_cost,
    br.amortized_brand_budget,
    ba.amortized_brand_supply_cost,
    bd.amortized_brand_demand_cost,
    bs.amortized_amortized_brand_supply_cost
FROM grouped_rentals_and_tickets AS rt
FULL OUTER JOIN marketing_costs_date_city AS mc
    ON rt.dt_month_start = mc.dt_month_start AND rt.city_group = mc.city_group
FULL OUTER JOIN supply_amortized AS sa
    ON rt.dt_month_start = sa.dt_month_start AND rt.city_group = sa.city_group
FULL OUTER JOIN branding_amortized AS br
    ON rt.dt_month_start = br.dt_month_start AND rt.city_group = br.city_group
FULL OUTER JOIN branding_supply_amortized AS ba
    ON rt.dt_month_start = ba.dt_month_start AND rt.city_group = ba.city_group
FULL OUTER JOIN branding_demand_amortized AS bd
    ON rt.dt_month_start = bd.dt_month_start AND rt.city_group = bd.city_group
FULL OUTER JOIN brand_supply_amortized_amortized AS bs
    ON rt.dt_month_start = bs.dt_month_start AND rt.city_group = bs.city_group
