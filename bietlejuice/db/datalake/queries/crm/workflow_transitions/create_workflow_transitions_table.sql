SELECT
    CAST(json_extract(transition, '$._id') AS VARCHAR) AS id,
    id as id_workflow,
    CAST(json_extract(transition, '$.from.taskId') AS VARCHAR) AS id_task_from,
    CAST(json_extract(transition, '$.to.taskId') AS VARCHAR) AS id_task_to,
    CAST(json_extract(transition, '$.assignmentMethod') AS VARCHAR) AS assignment_method,
    CAST(json_extract(transition, '$.from.taskDefinition') AS VARCHAR) AS definition_task_from,
    CAST(json_extract(transition, '$.to.taskDefinition') AS VARCHAR) AS definition_task_to,
    COALESCE(CAST(json_extract(transition, '$.to.endWorkflow') AS BOOLEAN),false) AS is_end_of_workflow,
    json_extract(transition, '$.context') AS context,
    CAST(SUBSTRING(CAST(json_extract(transition, '$.date') AS VARCHAR),1,19) AS TIMESTAMP) AS ts_transitioned,
    dt
FROM datalake_clean.crm_workflows
CROSS JOIN
	UNNEST(CAST(json_parse(transitions) AS array(json))) AS t(transition)
WHERE dt = '__PARTITION_DATE__'
;