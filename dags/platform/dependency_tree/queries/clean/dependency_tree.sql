SELECT
    CAST(dag AS STRING) AS id_dag,
    CAST(up_level_dag_dependency AS STRING) AS id_dependency_dag,
    CAST(up_level_task_dependency AS STRING) AS id_dependency_task,
    CAST(up_level_run_suffix AS STRING) AS dependency_run_suffix,
    CAST(level AS INTEGER) AS dependency_depth,
    CASE WHEN level = 0 THEN TRUE ELSE FALSE END AS is_direct_dependency,
    MAX(level) OVER (PARTITION BY dag) AS dag_max_depth
FROM
    datalake_dependency_tree_raw.dependency_tree
