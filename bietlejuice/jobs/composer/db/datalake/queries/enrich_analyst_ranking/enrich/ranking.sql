WITH agents_metrics AS (
  SELECT
    id_agent,
    department,
    SUM(COALESCE(closed_demand,0)) AS closed_demand,
    SUM(COALESCE(tickets_solved_in_time,0)) AS tickets_solved_in_time,
    SUM(COALESCE(tickets_not_solved_in_time,0)) AS tickets_not_solved_in_time,
    SUM(COALESCE(sum_csat_satisfied_score,0)) AS sum_csat_satisfied_score,
    SUM(COALESCE(total_tickets_with_csat_score,0)) AS total_tickets_with_csat_score,
    SUM(COALESCE(total_tickets_resolution,0)) AS total_tickets_resolution,
    SUM(COALESCE(total_tickets_answered_resolution,0)) AS total_tickets_answered_resolution,
    SUM(COALESCE(NULL,0)) AS ra_would_do_business_again, --REPLACE HERE WITH REAL DATA
    SUM(COALESCE(NULL,0)) AS ra_score, --REPLACE HERE WITH REAL DATA
    SUM(COALESCE(NULL,0)) AS ra_solution, --REPLACE HERE WITH REAL DATA
    DATE(DATE_TRUNC('week',am.dt_metric_reference)) AS dt_ranking_week
  FROM
    datalake_analyst_ranking.analyst_metrics am
  WHERE
    DATE_TRUNC('week',am.dt_metric_reference) = DATE_TRUNC('week', '{year}-{month}-{day}')
  GROUP BY id_agent, department, DATE(DATE_TRUNC('week',am.dt_metric_reference))
),
weekly_achiev AS (
  SELECT
    id_agent,
    art.id_group,
    department,
    CASE
      WHEN productivity_weight <> 0 THEN 1
      WHEN (closed_demand/productivity_target) >= 1 THEN 1
      WHEN (closed_demand/productivity_target) BETWEEN 0.8 AND 1 THEN 0.9
      WHEN (closed_demand/productivity_target) BETWEEN 0.6 AND 0.8 THEN 0.75
      WHEN (closed_demand/productivity_target) < 0.6 THEN 0
    END AS multiplication_factor,
    COALESCE((closed_demand/productivity_target) * productivity_weight , 0) AS productivity,
    COALESCE(((tickets_solved_in_time/(tickets_solved_in_time + tickets_not_solved_in_time))/target_sla) * sla_weight , 0) AS sla,
    COALESCE(((sum_csat_satisfied_score/total_tickets_with_csat_score)/target_csat) * csat_weight , 0) AS csat,
    COALESCE(((total_tickets_resolution/total_tickets_answered_resolution)/target_resolution) * resolution_weight , 0) AS resolution,
    COALESCE((ra_would_do_business_again/ra_would_do_business_again_target) * would_do_business_again_weight , 0) AS ra_would_do_business_again,
    COALESCE((ra_score/ra_target_score) * reclameaqui_note_weight , 0) AS ra_score,
    COALESCE((ra_solution/ra_target_solution_rate) * solution_rate_weight , 0) AS ra_solution,
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
    multiplication_factor,
    (productivity + sla + csat + resolution + ra_would_do_business_again + ra_score + ra_solution) * multiplication_factor AS ranking_score,
    dt_ranking_week
  FROM
    weekly_achiev
)
SELECT
    id_agent,
    id_group,
    department,
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
