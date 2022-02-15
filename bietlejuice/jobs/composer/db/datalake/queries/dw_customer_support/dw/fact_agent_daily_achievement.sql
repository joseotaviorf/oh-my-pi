WITH achievement AS (
    SELECT
        MD5(CONCAT(ap.sk_agent, ap.sk_date, ap.sk_agent_manager, ap.sk_department)) AS sk_achievement,
        ap.sk_agent,
        ap.sk_agent_manager,
        ap.sk_department,
        ap.sk_date,
        (ap.total_csat_satisfied_score/ap.total_tickets_with_csat_score)/rt.target_csat AS csat_satisfied_target_achievement,
        (ap.total_tickets_resolution/ap.total_tickets_answered_resolution)/rt.target_resolution AS resolution_rate_target_achievement,
        (ap.total_tickets+COALESCE(ap.total_crm_tasks_solved,0))/rt.target_productivity AS closed_tickets_target_achievement,
        ((ap.total_minutes_resolution_time/ap.total_tickets)/1440.0)/rt.target_frt AS avg_days_resolution_target_achievement,
        ap.dt,
        ap.year,
        ap.month,
        ap.day
    FROM 
        dw_customer_support.fact_agent_daily_productivity ap
    LEFT JOIN 
        dw_customer_support.dim_ranking_targets rt
            ON ap.sk_agent_manager = rt.sk_team_leader
            AND ap.sk_department = rt.sk_department
            AND ap.dt BETWEEN rt.dt_start and rt.dt_end
),
score AS (
    SELECT
        sk_achievement,
        (csat_satisfied_target_achievement+resolution_rate_target_achievement+closed_tickets_target_achievement+avg_days_resolution_target_achievement)/4 AS achievement_weighted_score,
        dt
    FROM
        achievement
)
SELECT
    s.sk_achievement,
    sk_agent,
    sk_agent_manager,
    sk_department,
    sk_date,
    csat_satisfied_target_achievement,
    resolution_rate_target_achievement,
    closed_tickets_target_achievement,
    avg_days_resolution_target_achievement,
    PERCENT_RANK() OVER (PARTITION BY s.dt ORDER BY s.achievement_weighted_score) AS ranking_percent_position,
    ROUND(PERCENT_RANK() OVER (PARTITION BY s.dt ORDER BY s.achievement_weighted_score),1) AS ranking_10th_percentile_position,
    RANK() OVER (PARTITION BY s.dt ORDER BY s.achievement_weighted_score DESC) AS ranking_position,
    RANK() OVER (PARTITION BY s.dt, sk_department ORDER BY s.achievement_weighted_score DESC) AS department_ranking_position,
    s.dt,
    NOW() AS ts_load,
    year,
    month,
    day
FROM 
    score s
LEFT JOIN
    achievement a
        ON a.sk_achievement = s.sk_achievement
WHERE 
    achievement_weighted_score IS NOT NULL
    AND s.dt = DATE('{year}-{month}-{day}')