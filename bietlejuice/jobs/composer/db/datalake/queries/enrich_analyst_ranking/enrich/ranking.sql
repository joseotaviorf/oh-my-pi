WITH agents_metrics AS (
  SELECT
    id_agent,
    department,
    MIN(agent_age_in_months) AS agent_age_in_months,
    SUM(COALESCE(closed_demand,0)) AS closed_demand,
    SUM(COALESCE(tickets_solved_in_time,0)) AS tickets_solved_in_time,
    SUM(COALESCE(tickets_not_solved_in_time,0)) AS tickets_not_solved_in_time,
    SUM(COALESCE(sum_csat_satisfied_score,0)) AS sum_csat_satisfied_score,
    SUM(COALESCE(total_tickets_with_csat_score,0)) AS total_tickets_with_csat_score,
    SUM(COALESCE(total_tickets_resolution,0)) AS total_tickets_resolution,
    SUM(COALESCE(total_tickets_answered_resolution,0)) AS total_tickets_answered_resolution,
    SUM(COALESCE(ra_would_do_business_again,0)) AS ra_would_do_business_again,
    CASE 
      WHEN COALESCE(ra_total_tickets_rated,0) <> 0 THEN (SUM(ra_score_sum)/SUM(ra_total_tickets_rated))
      ELSE 0 
    END AS ra_score,
    SUM(COALESCE(ra_solved_tickets,0)) AS ra_solved_tickets,
    SUM(COALESCE(ra_total_tickets_rated,0)) AS ra_total_tickets_rated,
    DATE(DATE_TRUNC('week',am.dt_metric_reference)) AS dt_ranking_week
  FROM
    datalake_analyst_ranking.analyst_metrics am
  WHERE
    DATE_TRUNC('week',am.dt_metric_reference) BETWEEN DATE_TRUNC('week', DATE('{year}-{month}-{day}') - INTERVAL 1 DAYS) AND DATE_TRUNC('week', '{year}-{month}-{day}')
  GROUP BY id_agent, department, DATE(DATE_TRUNC('week',am.dt_metric_reference))
),
weekly_achiev AS (
  SELECT
    id_agent,
    art.id_group,
    department,
    agent_age_in_months,
    CASE
      WHEN productivity_weight <> 0 THEN 1
      WHEN (closed_demand/productivity_target) >= 1 THEN 1
      WHEN (closed_demand/productivity_target) BETWEEN 0.8 AND 1 THEN 0.9
      WHEN (closed_demand/productivity_target) BETWEEN 0.6 AND 0.8 THEN 0.75
      WHEN (closed_demand/productivity_target) < 0.6 THEN 0
    END AS multiplication_factor,
    resolution_weight,
    sla_weight,
    productivity_weight,
    csat_weight,
    would_do_business_again_weight,
    reclameaqui_note_weight,
    solution_rate_weight,
    COALESCE((closed_demand/productivity_target), 0) AS productivity_achievement,
    COALESCE(((tickets_solved_in_time/(tickets_solved_in_time + tickets_not_solved_in_time))/target_sla), 0) AS sla_achievement,
    COALESCE(((sum_csat_satisfied_score/total_tickets_with_csat_score)/target_csat), 0) AS csat_achievement,
    COALESCE(((total_tickets_resolution/total_tickets_answered_resolution)/target_resolution), 0) AS resolution_achievement,
    COALESCE(((ra_would_do_business_again/ra_total_tickets_rated)/ra_would_do_business_again_target), 0) AS ra_would_do_business_again_achievement,
    COALESCE((ra_score/ra_target_score) , 0) AS ra_score_achievement,
    COALESCE(((ra_solved_tickets/ra_total_tickets_rated)/ra_target_solution_rate) , 0) AS ra_solution_achievement,
    dt_ranking_week
  FROM
    agents_metrics am
  JOIN
   datalake_gsheets_clean.ranking_rules rr
     ON rr.type = am.department
  JOIN
    datalake_gsheets_clean.agents_ranking_targets art
      ON am.department = art.team
      AND am.dt_ranking_week BETWEEN art.dt_start AND DATE(COALESCE(dt_end, NOW()))
),
ranking_score AS (
  SELECT
    id_agent,
    id_group,
    department,
    agent_age_in_months,
    multiplication_factor,
    productivity_achievement,
    sla_achievement,
    csat_achievement,
    resolution_achievement,
    ra_would_do_business_again_achievement,
    ra_score_achievement,
    ra_solution_achievement,
    (
      (productivity_achievement * productivity_weight)
      + (sla_achievement * sla_weight)
      + (csat_achievement * csat_weight)
      + (resolution_achievement * resolution_weight)
      + (ra_would_do_business_again_achievement * would_do_business_again_weight)
      + (ra_score_achievement * reclameaqui_note_weight)
      + (ra_solution_achievement * solution_rate_weight)
    ) * multiplication_factor AS ranking_score,
    dt_ranking_week
  FROM
    weekly_achiev
)
SELECT
    id_agent,
    id_group,
    department,
    agent_age_in_months,
    productivity_achievement,
    sla_achievement,
    csat_achievement,
    resolution_achievement,
    ra_would_do_business_again_achievement,
    ra_score_achievement,
    ra_solution_achievement,
    multiplication_factor,
    ranking_score,
    CASE 
        WHEN PERCENT_RANK() OVER (PARTITION BY id_group ORDER BY ranking_score) < 0.25 THEN 'Q4'
        WHEN PERCENT_RANK() OVER (PARTITION BY id_group ORDER BY ranking_score) < 0.5 THEN 'Q3'
        WHEN PERCENT_RANK() OVER (PARTITION BY id_group ORDER BY ranking_score) < 0.75 THEN 'Q2'
        WHEN PERCENT_RANK() OVER (PARTITION BY id_group ORDER BY ranking_score) >= 0.75 THEN 'Q1'
    END AS ranking_quartile,
    PERCENT_RANK() OVER (PARTITION BY id_group ORDER BY ranking_score) AS ranking_percent_position,
    RANK() OVER (PARTITION BY id_group ORDER BY ranking_score DESC) AS ranking_position,
    dt_ranking_week
FROM
    ranking_score
