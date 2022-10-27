SELECT 
    YEAR(dt_week_started) AS base_year,
    dt_week_started AS week_start,
    country_code AS country_name,
    city_group,
    supply_mkt_origin, 
    supply_mkt_origin_detailed,
    mexico_channel,     
    leads,
    -- Coincident actual volumes
    prospects,
    qualifieds,
    opportunities,
    first_listings,
    -- Cohort actual volumes
    prospects_cohort,
    qualifieds_cohort,
    opportunities_cohort,
    first_listings_cohort,
    -- Coincident "conversions"
    l2p_coincident,
    p2q_coincident,
    q2o_coincident,
    o2fl_coincident,
    -- Cohort conversions
    l2p_cohort,
    p2q_cohort,
    q2o_cohort,
    o2fl_cohort,
    -- Actual volume targets
    leads_targets,
    prospects_targets,
    qualifieds_targets,
    opportunities_targets,
    first_listings_targets,
    -- Actual costs
    actual_cost,
    actual_cost_comission,
    cost,
    -- Cost targets 
    budget_total_target,
    budget_comission_target,
    budget_target,
    -- Listings
    ongoing_listings,
    net_churn
FROM 
    datalake_mexico_rent_supply.weekly_supply_funnel