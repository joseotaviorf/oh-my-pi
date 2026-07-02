-- Initiative-level cost cohort rules. Single source of truth replacing the
-- inline CASE in Superset dataset 21202 (dashboard data-platform-cost-all-cohorts).
-- Consumed by dw_databricks_costs.fact_databricks_costs and
-- dw_databricks_health.fact_databricks_task_run; lowest priority wins (MIN_BY).
-- rule_type contract:
--   team_owner_exact  : team_owner = match_value
--   team_owner_prefix : team_owner LIKE match_value || '%'
--   provisioner_exact : provisioner(_resolved) = match_value
--   workload_prefix   : LOWER(workload identity) LIKE match_value || '%'
--   workload_like     : LOWER(workload identity) LIKE match_value
WITH cohort_rules (priority, rule_type, match_value, cost_cohort, rule_note) AS (
    VALUES
        (10, 'team_owner_exact',  'mlops',                  'quintoml_wonka', 'QuintoML/Wonka pipelines on the bietlejuice fleet carry owner=mlops'),
        (20, 'provisioner_exact', 'wonka',                  'quintoml_wonka', 'Wonka streaming clusters'),
        (21, 'provisioner_exact', 'quintoml',               'quintoml_wonka', 'QuintoML-provisioned job clusters'),
        (22, 'provisioner_exact', 'quintoml-ml',            'quintoml_wonka', 'untagged batch-predict fallback (fact heuristic)'),
        (30, 'workload_prefix',   'quintoml.',              'quintoml_wonka', 'Airflow DAG id prefix'),
        (31, 'workload_prefix',   'wonka.',                 'quintoml_wonka', 'Airflow DAG id prefix'),
        (32, 'workload_like',     '%batch-predict%',        'quintoml_wonka', 'ML batch scoring job names'),
        (33, 'workload_like',     '%batch_predict%',        'quintoml_wonka', 'ML batch scoring job names (underscore variant)'),
        (40, 'provisioner_exact', 'customer-data-platform', 'cdp',            'CDP/CRM Lakeflow jobs'),
        (50, 'team_owner_prefix', 'tech-platform-',         'tech_platform',  'Tech Platform-owned DAGs on the bietlejuice fleet; split out to avoid double counting in consolidated reports'),
        (60, 'workload_prefix',   'bietlejuice.',           'bietlejuice',    'DAG Builder pipelines by canonical Airflow id'),
        (61, 'provisioner_exact', 'bietlejuice',            'bietlejuice',    'bietlejuice-provisioned fleet fallback')
)
SELECT
    priority,
    rule_type,
    match_value,
    cost_cohort,
    rule_note,
    CURRENT_TIMESTAMP() AS ts_load
FROM cohort_rules
