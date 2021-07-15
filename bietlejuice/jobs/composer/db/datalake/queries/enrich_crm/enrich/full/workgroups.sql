SELECT DISTINCT
    id,
    EXPLODE(FROM_JSON(task_types,'ARRAY<STRING>')) AS task_type,
    title
FROM datalake_crm_clean.workgroups