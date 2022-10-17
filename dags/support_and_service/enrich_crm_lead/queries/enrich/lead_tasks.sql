SELECT
    task_status.id_origin AS id_lead,
    task_status.id_rep,
    task_status.ts_created,
    task_status.ts_closed,
    ROW_NUMBER() OVER (PARTITION BY task_status.id_origin ORDER BY task_status.ts_created ASC) AS lead_task_order,
    ROW_NUMBER() OVER (PARTITION BY task_status.id_origin ORDER BY task_status.ts_created DESC) AS lead_task_inverse_order
FROM
    datalake_crm_tasks.task_status
WHERE
    task_status.type IN ('ConverterLead', 'ConverterLeadPrioritario')