WITH weekly_results AS (
    WITH total_departments AS (
        SELECT
            sk_agent,
            DATE_TRUNC('week', dt) AS week_start,
            COUNT(DISTINCT sk_department) AS total_departments
        FROM 
            dw_customer_support.fact_agent_daily_productivity ap
        GROUP BY 1,2
    )
    SELECT
        MD5(CONCAT(ap.sk_agent, ap.sk_agent_manager, ap.sk_department, td.week_start)) AS sk_achievement,
        ap.sk_agent,
        sk_agent_manager,
        DATE_TRUNC('week', dt) AS week_start,
        MAX(sk_department) AS sk_department,
        MAX(total_departments) AS total_departments,
        SUM(COALESCE(ap.total_tickets,0))+SUM(COALESCE(ap.total_crm_tasks_solved,0)) AS total_productivity_result,
        SUM(COALESCE(ap.total_csat_satisfied_score,0))/SUM(COALESCE(ap.total_tickets_with_csat_score,0)) AS avg_csat_satisfied_result,
        SUM(COALESCE(ap.total_tickets_resolution,0))/SUM(COALESCE(ap.total_tickets_answered_resolution,0)) AS avg_resolution_rate_result,
        (SUM(ap.total_minutes_resolution_time)/1440.0)/SUM(ap.total_tickets) AS avg_days_resolution_result
    FROM
        dw_customer_support.fact_agent_daily_productivity ap
    LEFT JOIN
        total_departments td
            ON td.sk_agent = ap.sk_agent
            AND DATE_TRUNC('week', ap.dt) = td.week_start
    GROUP BY 1,2,3,4
),
achievement AS (
    SELECT
        rt.sk_achievement,
        rt.total_productivity_result/tg.target_productivity AS closed_tickets_target_achievement,
        rt.avg_csat_satisfied_result/tg.target_csat AS csat_satisfied_target_achievement,
        rt.avg_resolution_rate_result/tg.target_resolution AS resolution_rate_target_achievement,
        tg.target_frt/rt.avg_days_resolution_result AS avg_days_resolution_target_achievement,
        CASE 
            WHEN (total_productivity_result/tg.target_productivity) >= 1 
                THEN ((rt.avg_csat_satisfied_result/tg.target_csat)*0.4+(avg_resolution_rate_result/tg.target_resolution)*0.4+(tg.target_frt/rt.avg_days_resolution_result)*0.2)
            WHEN (total_productivity_result/tg.target_productivity) >= 0.8
                THEN ((rt.avg_csat_satisfied_result/tg.target_csat)*0.4+(avg_resolution_rate_result/tg.target_resolution)*0.4+(tg.target_frt/rt.avg_days_resolution_result)*0.2)*0.9
            WHEN (total_productivity_result/tg.target_productivity) >= 0.6
                THEN ((rt.avg_csat_satisfied_result/tg.target_csat)*0.4+(avg_resolution_rate_result/tg.target_resolution)*0.4+(tg.target_frt/rt.avg_days_resolution_result)*0.2)*0.75
            WHEN (total_productivity_result/tg.target_productivity) < 0.6
                THEN 0
        END AS achievement_weighted_score
    FROM 
        dw_customer_support.dim_ranking_targets tg
    LEFT JOIN
        weekly_results rt
            ON rt.sk_agent_manager = tg.sk_team_leader
            AND rt.sk_department = tg.sk_department
            AND rt.week_start BETWEEN tg.dt_start AND tg.dt_end
)
SELECT
    ac.sk_achievement,
    wr.sk_agent,
    wr.sk_agent_manager,
    wr.sk_department,
    wr.total_departments,
    ac.achievement_weighted_score,
    CASE 
        WHEN PERCENT_RANK() OVER (PARTITION BY wr.week_start ORDER BY ac.achievement_weighted_score) < 0.25 THEN 'Q4'
        WHEN PERCENT_RANK() OVER (PARTITION BY wr.week_start ORDER BY ac.achievement_weighted_score) < 0.5 THEN 'Q3'
        WHEN PERCENT_RANK() OVER (PARTITION BY wr.week_start ORDER BY ac.achievement_weighted_score) < 0.75 THEN 'Q2'
        WHEN PERCENT_RANK() OVER (PARTITION BY wr.week_start ORDER BY ac.achievement_weighted_score) >= 0.75 THEN 'Q1'
    END AS ranking_quartile,
    PERCENT_RANK() OVER (PARTITION BY wr.week_start ORDER BY ac.achievement_weighted_score) AS ranking_percent_position,
    RANK() OVER (PARTITION BY wr.week_start ORDER BY ac.achievement_weighted_score DESC) AS ranking_position,
    ac.closed_tickets_target_achievement,
    ac.csat_satisfied_target_achievement,
    ac.resolution_rate_target_achievement,
    ac.avg_days_resolution_target_achievement,
    DATE(wr.week_start) AS dt_week_started,
    NOW() AS ts_load,
    YEAR(wr.week_start) AS year,
    MONTH(wr.week_start) AS month,
    DAY(wr.week_start) AS day
FROM
    achievement ac
LEFT JOIN 
    weekly_results wr
        ON wr.sk_achievement = ac.sk_achievement
WHERE 
    ac.achievement_weighted_score IS NOT NULL
    AND wr.week_start = DATE_TRUNC('week', DATE('{year}-{month}-{day}'))