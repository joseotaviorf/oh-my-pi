WITH goal_category AS (
  SELECT
    g.id_goal,
    CASE
      WHEN g.goal_category IN ('ProjetoOuProcessoCriticoProjec', 'Projeto ou Processo Crítico') THEN 'project'
      WHEN g.goal_category IN ('Indicador/KPI', 'IndicadorKpi') THEN 'kpi'
      ELSE g.goal_category
    END AS category
  FROM
    datalake_pin_goal_clean.goal AS g
  WHERE
    g.goal_version_type_code = 'ACTIVE'
),
goal_base AS (
  SELECT
    g.id_goal,
    ap.person_number,
    ab.person_number AS assigned_by_person_number,
    im.name,
    rpt.review_period_name,
    gpt.goal_plan_name,
    g.goal_name,
    g.expected_completion_period,
    gc.category,
    CASE
      WHEN gc.category <> 'kpi' THEN NULL
      WHEN g.attribute1_text = 'Valor/Value' THEN 'value'
      WHEN g.attribute1_text = 'Percentual/Percentage/Porcenta' THEN 'percentage'
      WHEN g.attribute1_text = 'Número/Number/Numero' THEN 'number'
      ELSE g.attribute1_text
    END AS measurement_unit,
    CASE
      WHEN gc.category <> 'kpi' THEN NULL
      WHEN g.attribute2_text = 'Quanto maior, melhor/The bigger the better/Cuanto más grande, mejor' THEN 'maximize'
      WHEN g.attribute2_text = 'Quanto menor, melhor/The smaller the better/Cuanto más pequeño mejor' THEN 'minimize'
      ELSE g.attribute2_text
    END AS goal_orientation,
    gpg.goal_weight,
    CASE
      WHEN gc.category = 'kpi' THEN g.attribute_number1_value
      WHEN gc.category = 'project' THEN g.attribute1_text
      ELSE NULL
    END AS minimum_value,
    CASE
      WHEN gc.category = 'kpi' THEN g.attribute_number2_value
      WHEN gc.category = 'project' THEN g.attribute2_text
      ELSE NULL
    END AS target_value,
    CASE
      WHEN gc.category = 'kpi' THEN g.attribute_number3_value
      WHEN gc.category = 'project' THEN g.attribute3_text
      ELSE NULL
    END AS maximum_value,
    CASE
      WHEN gc.category = 'kpi' THEN g.attribute_number4_value
      WHEN gc.category = 'project' THEN g.attribute_number1_value
      ELSE NULL
    END AS result_value,
    g.dt_started,
    g.dt_target_completion,
    g.ts_modified,
    g.ts_created,
    g.ts_updated,
    g.ts_load
  FROM
    datalake_pin_goal_clean.goal AS g
  INNER JOIN
    goal_category AS gc
      ON gc.id_goal = g.id_goal
  INNER JOIN
    datalake_pin_goal_clean.goal_plan_to_goal AS gpg
      ON gpg.id_goal = g.id_goal
  INNER JOIN
    datalake_pin_goal_clean.goal_plan_translation AS gpt
      ON gpt.id_goal_plan = gpg.id_goal_plan
        AND gpt.language = 'PTB'
  INNER JOIN
    datalake_pin_talent_clean.review_period_translation AS rpt
      ON rpt.id_review_period = gpg.id_review_period
        AND rpt.language = 'PTB'
  INNER JOIN
    datalake_people.identifier_mapping AS im
      ON im.id_person = g.id_person
        AND im.is_person_latest_assignment
  INNER JOIN
    datalake_pin_core_clean.all_people AS ap
      ON ap.id_person = g.id_person
        AND ap.dt_effective_ended >= '9999-12-31'
  INNER JOIN
    datalake_pin_core_clean.all_people AS ab
      ON ab.id_person = g.id_assigned_by_person
        AND ab.dt_effective_ended >= '9999-12-31'
  WHERE
    gc.category IN ('kpi', 'project')
),
goal_values AS (
  SELECT
    g.id_goal,
    CASE
      WHEN b.minimum_value IS NULL THEN NULL
      WHEN b.goal_orientation = 'minimize' THEN GREATEST(CAST(b.maximum_value AS DOUBLE), CAST(b.minimum_value AS DOUBLE))
      WHEN b.goal_orientation = 'maximize' THEN LEAST(CAST(b.maximum_value AS DOUBLE), CAST(b.minimum_value AS DOUBLE))
      ELSE NULL
    END AS minimum_value,
    b.target_value,
    CASE
      WHEN b.maximum_value IS NULL THEN NULL
      WHEN b.goal_orientation = 'minimize' THEN LEAST(CAST(b.maximum_value AS DOUBLE), CAST(b.minimum_value AS DOUBLE))
      WHEN b.goal_orientation = 'maximize' THEN GREATEST(CAST(b.maximum_value AS DOUBLE), CAST(b.minimum_value AS DOUBLE))
      ELSE NULL
    END AS maximum_value
  FROM 
    datalake_pin_goal_clean.goal AS g
  LEFT JOIN
    goal_base AS b 
      ON b.id_goal = g.id_goal
  WHERE
    b.category = 'kpi'
  UNION ALL
  SELECT
    g.id_goal,
    b.minimum_value,
    b.target_value,
    b.maximum_value
  FROM 
    datalake_pin_goal_clean.goal AS g
  LEFT JOIN
    goal_base AS b
      ON b.id_goal = g.id_goal
  WHERE
    b.category = 'project'
),
project_achievements AS (
  SELECT
    b.id_goal,
    CASE
      WHEN b.result_value IS NULL THEN NULL
      ELSE CAST(b.result_value AS DOUBLE) * 0.01
    END AS achievement_percentage_raw
  FROM
    goal_base AS b
  WHERE
    b.category = 'project'
),
kpi_full_achievements AS (
  SELECT
    b.id_goal,
    CASE
      WHEN b.result_value IS NULL THEN NULL
      WHEN CAST(b.result_value AS DOUBLE) <= v.target_value THEN (TRY_DIVIDE((CAST(b.result_value AS DOUBLE) - v.minimum_value), (v.target_value - v.minimum_value)) * (1 - 0.7)) + 0.7
      WHEN CAST(b.result_value AS DOUBLE) > v.target_value THEN (TRY_DIVIDE((CAST(b.result_value AS DOUBLE) - v.target_value), (v.maximum_value - v.target_value)) * (1.2 - 1)) + 1
      ELSE NULL
    END AS achievement_percentage_raw
  FROM
    goal_base AS b
  LEFT JOIN
    goal_values AS v 
      ON v.id_goal = b.id_goal
  WHERE
    b.category = 'kpi'
    AND v.minimum_value IS NOT NULL
    AND v.target_value IS NOT NULL
    AND v.maximum_value IS NOT NULL
),
kpi_partial_achievements AS (
  SELECT
    b.id_goal,
    CASE
      WHEN b.result_value IS NULL THEN NULL
      WHEN b.goal_orientation = 'maximize' THEN TRY_DIVIDE(CAST(b.result_value AS DOUBLE) - v.target_value, ABS(v.target_value)) + 1
      WHEN b.goal_orientation = 'minimize' THEN TRY_DIVIDE(v.target_value - CAST(b.result_value AS DOUBLE), ABS(v.target_value)) + 1
      ELSE NULL
    END AS achievement_percentage_raw
  FROM
    goal_base AS b
  LEFT JOIN
    goal_values AS v
      ON v.id_goal = b.id_goal
  WHERE
    b.category = 'kpi'
    AND (v.minimum_value IS NULL OR v.maximum_value IS NULL)
),
goal_achievements AS (
  SELECT
    pa.id_goal,
    CASE
      WHEN pa.achievement_percentage_raw IS NULL THEN NULL
      ELSE LEAST(GREATEST(pa.achievement_percentage_raw, 0.0), 1.2)
    END AS achievement_percentage
  FROM
    project_achievements AS pa
  UNION ALL
  SELECT
    kfa.id_goal,
    CASE
      WHEN kfa.achievement_percentage_raw IS NULL THEN NULL
      ELSE LEAST(GREATEST(kfa.achievement_percentage_raw, 0.0), 1.2)
    END AS achievement_percentage
  FROM
    kpi_full_achievements AS kfa
  UNION ALL
    SELECT
    kpa.id_goal,
    CASE
      WHEN kpa.achievement_percentage_raw IS NULL THEN NULL
      ELSE LEAST(GREATEST(kpa.achievement_percentage_raw, 0.0), 1.2)
    END AS achievement_percentage
  FROM
    kpi_partial_achievements AS kpa
)
SELECT
  b.id_goal,
  b.person_number,
  b.assigned_by_person_number,
  b.name,
  b.review_period_name,
  b.goal_plan_name,
  b.goal_name,
  b.expected_completion_period,
  b.category,
  b.measurement_unit,
  b.goal_orientation,
  b.goal_weight,
  v.minimum_value,
  v.target_value,
  v.maximum_value,
  b.result_value,
  ga.achievement_percentage,
  b.dt_started,
  b.dt_target_completion,
  b.ts_modified,
  b.ts_created,
  b.ts_updated,
  b.ts_load
FROM 
  goal_base AS b
LEFT JOIN
  goal_values AS v 
    ON v.id_goal = b.id_goal
LEFT JOIN
  goal_achievements AS ga 
    ON ga.id_goal = b.id_goal
WHERE
    b.category IN ('kpi', 'project')