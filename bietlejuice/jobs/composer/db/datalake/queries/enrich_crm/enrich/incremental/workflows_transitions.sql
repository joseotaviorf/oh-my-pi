WITH exploded_transitions AS (
    SELECT 
        id,
        status,
        start_date_object,
        updated_date_object,
        end_date_object,
        EXPLODE(
            FROM_JSON(REPLACE(transitions,'$',''), 
            'ARRAY<
                STRUCT<
                    assignmentMethod: STRING, 
                    _id: STRUCT<oid: STRING>, 
                    from: STRUCT<taskDefinition: STRING,taskId: STRUCT<oid: STRING>>,
                    to: STRUCT<endWorkflow: STRING, taskDefinition: STRING,taskId: STRUCT<oid: STRING>>,
                    date: STRUCT<date: TIMESTAMP>,
                    context: STRING
                >
            >'
        )) AS transition,
        year,
        month,
        day
    FROM
        datalake_crm_clean.workflows
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
)
SELECT
    transition._id.oid AS id_transition,
    GET_JSON_OBJECT(REPLACE(id,'$',''),'$.oid') AS id_workflow,
    transition.from.taskId.oid AS id_task_from,
    transition.to.taskId.oid AS id_task_to,
    status,
    transition.assignmentMethod AS assignment_method,
    transition.from.taskDefinition AS definition_task_from,
    transition.to.taskDefinition AS definition_task_to,
    transition.context AS context,
    COALESCE(CAST(transition.to.endWorkflow AS BOOLEAN), false) AS is_end_of_workflow,
    CAST(GET_JSON_OBJECT(REPLACE(start_date_object,'$',''),'$.date') AS TIMESTAMP) AS ts_workflow_started,
    CAST(GET_JSON_OBJECT(REPLACE(updated_date_object,'$',''),'$.date') AS TIMESTAMP) AS ts_workflow_updated,
    CAST(GET_JSON_OBJECT(REPLACE(end_date_object,'$',''),'$.date') AS TIMESTAMP) AS ts_workflow_ended,
    transition.date.date AS ts_transitioned,
    year,
    month,
    day
FROM
    exploded_transitions
WHERE
    DATE(transition.date.date) = DATE('{year}-{month}-{day}')
