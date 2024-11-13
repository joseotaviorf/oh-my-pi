SELECT
	dag::STRING,
	level_dag_dependency::STRING,
	up_level_dag_dependency::STRING,
	up_level_task_dependency::STRING,
	level::INTEGER
FROM
    datalake_dependency_tree_raw.dependency_tree