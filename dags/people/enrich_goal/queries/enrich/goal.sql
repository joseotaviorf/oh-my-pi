WITH goal_category AS (
  SELECT
    g.id_goal,
    CASE
      WHEN g.goal_category IN ('ProjetoOuProcessoCriticoProjec', 'Projeto ou Processo Crítico') THEN 'project'
      WHEN g.goal_category IN ('Indicador/KPI', 'IndicadorKpi') THEN 'kpi'
      ELSE g.goal_category
    END AS category
  FROM
    datalake_pin_goal_clean.goal g
  WHERE
    g.goal_version_type_code = 'ACTIVE'
),
goal_base AS (
  SELECT
    g.id_goal,
    ap.person_number,
    ab.person_number AS assigned_by_person_number,
    pn.display_name,
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
    datalake_pin_goal_clean.goal g
  INNER JOIN
    goal_category gc
    ON gc.id_goal = g.id_goal
  INNER JOIN
    datalake_pin_goal_clean.goal_plan_to_goal gpg
    ON gpg.id_goal = g.id_goal
  INNER JOIN
    datalake_pin_goal_clean.goal_plan_translation gpt
    ON gpt.id_goal_plan = gpg.id_goal_plan
      AND gpt.language = 'PTB'
  INNER JOIN
    datalake_pin_talent_clean.review_period_translation rpt
    ON rpt.id_review_period = gpg.id_review_period
      AND rpt.language = 'PTB'
  INNER JOIN
    datalake_pin_core_clean.person_name pn
    ON pn.id_person = g.id_person
      AND pn.name_type = 'GLOBAL'
      AND pn.dt_effective_ended >= '4712-12-31'
  INNER JOIN
    datalake_pin_core_clean.all_people ap
    ON ap.id_person = g.id_person
      AND ap.dt_effective_ended >= '4712-12-31'
  INNER JOIN
    datalake_pin_core_clean.all_people ab
    ON ab.id_person = g.id_assigned_by_person
      AND ab.dt_effective_ended >= '4712-12-31'
  WHERE
    gc.category IN ('kpi', 'project')
),
goal_with_achievement AS (
  SELECT
    id_goal,
    person_number,
    assigned_by_person_number,
    display_name,
    review_period_name,
    goal_plan_name,
    goal_name,
    expected_completion_period,
    category,
    measurement_unit,
    goal_orientation,
    goal_weight,
    minimum_value,
    target_value,
    maximum_value,
    result_value,
    CASE
      WHEN result_value IS NULL
      THEN NULL
      WHEN category = 'project'
      THEN CAST(result_value AS DOUBLE) * 0.01
      WHEN id_goal IS NULL
        OR goal_name IS NULL
        OR goal_orientation IS NULL
        OR result_value IS NULL
      THEN NULL
      WHEN category = 'kpi'
        AND minimum_value IS NOT NULL
        AND maximum_value IS NOT NULL
        AND goal_orientation = 'maximize'
        AND target_value IS NOT NULL
        AND CAST(result_value AS DOUBLE) >= CAST(minimum_value AS DOUBLE)
        AND CAST(result_value AS DOUBLE) <= CAST(target_value AS DOUBLE)
      THEN (((CAST(result_value AS DOUBLE) - CAST(minimum_value AS DOUBLE)) / (CAST(target_value AS DOUBLE) - CAST(minimum_value AS DOUBLE))) * (1.0 - 0.7)) + 0.7
      WHEN category = 'kpi'
        AND minimum_value IS NOT NULL
        AND maximum_value IS NOT NULL
        AND goal_orientation = 'maximize'
        AND target_value IS NOT NULL
        AND CAST(result_value AS DOUBLE) >= CAST(target_value AS DOUBLE)
        AND CAST(result_value AS DOUBLE) <= CAST(maximum_value AS DOUBLE)
      THEN (((CAST(result_value AS DOUBLE) - CAST(target_value AS DOUBLE)) / (CAST(maximum_value AS DOUBLE) - CAST(target_value AS DOUBLE))) * (1.2 - 1.0)) + 1.0
      WHEN category = 'kpi'
        AND minimum_value IS NOT NULL
        AND maximum_value IS NOT NULL
        AND goal_orientation = 'maximize'
        AND CAST(result_value AS DOUBLE) > CAST(maximum_value AS DOUBLE)
      THEN 1.2
      WHEN category = 'kpi'
        AND minimum_value IS NOT NULL
        AND maximum_value IS NOT NULL
        AND goal_orientation = 'minimize'
        AND target_value IS NOT NULL
        AND CAST(result_value AS DOUBLE) <= CAST(minimum_value AS DOUBLE)
        AND CAST(result_value AS DOUBLE) >= CAST(target_value AS DOUBLE)
      THEN (((CAST(minimum_value AS DOUBLE) - CAST(result_value AS DOUBLE)) / (CAST(minimum_value AS DOUBLE) - CAST(target_value AS DOUBLE))) * (1.0 - 0.7)) + 0.7
      WHEN category = 'kpi'
        AND minimum_value IS NOT NULL
        AND maximum_value IS NOT NULL
        AND goal_orientation = 'minimize'
        AND target_value IS NOT NULL
        AND CAST(result_value AS DOUBLE) <= CAST(target_value AS DOUBLE)
        AND CAST(result_value AS DOUBLE) >= CAST(maximum_value AS DOUBLE)
      THEN (((CAST(target_value AS DOUBLE) - CAST(result_value AS DOUBLE)) / (CAST(target_value AS DOUBLE) - CAST(maximum_value AS DOUBLE))) * (1.2 - 1.0)) + 1.0
      WHEN category = 'kpi'
        AND minimum_value IS NOT NULL
        AND maximum_value IS NOT NULL
        AND goal_orientation = 'minimize'
        AND CAST(result_value AS DOUBLE) < CAST(maximum_value AS DOUBLE)
      THEN 1.2
      WHEN category = 'kpi'
        AND (minimum_value IS NULL OR maximum_value IS NULL)
        AND goal_orientation = 'maximize'
        AND target_value IS NOT NULL
        AND CAST(target_value AS DOUBLE) > 0
      THEN CAST(result_value AS DOUBLE) / CAST(target_value AS DOUBLE)
      WHEN category = 'kpi'
        AND (minimum_value IS NULL OR maximum_value IS NULL)
        AND goal_orientation = 'minimize'
        AND result_value IS NOT NULL
        AND CAST(result_value AS DOUBLE) > 0
      THEN CAST(target_value AS DOUBLE) / CAST(result_value AS DOUBLE)
      ELSE NULL
    END AS achievement_percentage_raw,
    dt_started,
    dt_target_completion,
    ts_modified,
    ts_created,
    ts_updated,
    ts_load
  FROM
    goal_base
)
SELECT
  id_goal,
  person_number,
  assigned_by_person_number,
  display_name,
  review_period_name,
  goal_plan_name,
  goal_name,
  expected_completion_period,
  category,
  measurement_unit,
  goal_orientation,
  goal_weight,
  minimum_value,
  target_value,
  maximum_value,
  result_value,
  CASE
    WHEN achievement_percentage_raw IS NULL
    THEN NULL
    ELSE LEAST(GREATEST(achievement_percentage_raw, 0.0), 1.2)
  END AS achievement_percentage,
  dt_started,
  dt_target_completion,
  ts_modified,
  ts_created,
  ts_updated,
  ts_load
FROM
  goal_with_achievement
