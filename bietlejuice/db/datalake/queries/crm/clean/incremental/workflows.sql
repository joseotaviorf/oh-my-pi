SELECT
    _id AS id,
    workflowDefinitionId AS id_workflow_definition,
    flowId AS id_flow,
    workflowDefinitionVersion AS workflow_definition_version,
    __v AS version,
    states,
    status,
    transitions,
    context,
    startTime AS start_date_object,
    updated AS updated_date_object,
    endTime AS end_date_object,
    year,
    month,
    day
FROM
    datalake_crm_raw.workflows
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}