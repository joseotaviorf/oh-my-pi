SELECT
    dag::STRING AS id_dag,
    up_level_dag_dependency::STRING AS id_dependency_dag,
    up_level_task_dependency::STRING AS id_dependency_task,
    up_level_run_suffix::STRING AS dependency_run_suffix,
    level::INTEGER AS dependency_depth,
    CASE WHEN level = 0 THEN TRUE ELSE FALSE END AS is_direct_dependency,
    MAX(level) OVER (PARTITION BY dag) AS dag_max_depth
FROM
    datalake_dependency_tree_raw.dependency_tree
