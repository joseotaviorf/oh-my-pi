with json_entries as (
    select
        json_parse(workflows_entry) as workflows_entries,
        dt
    from datalake_raw.crm_workflows
    where dt = '__PARTITION_DATE__'
)
select
    cast(json_extract(workflows_entries, '$._id') as varchar) as id,
    json_format(json_extract(workflows_entries, '$.states')) as states,
    cast(json_extract(workflows_entries, '$.workflowDefinitionId') as varchar) as id_workflow_definition,
    cast(json_extract(workflows_entries, '$.workflowDefinitionVersion') as varchar) as workflow_definition_version,
    cast(json_extract(workflows_entries, '$.flowId') as varchar) as id_flow,
    cast(json_extract(workflows_entries, '$.startTime') as varchar) as ts_start,
    cast(json_extract(workflows_entries, '$.updated') as varchar) as ts_updated,
    cast(json_extract(workflows_entries, '$.status') as varchar) as status,
    json_format(json_extract(workflows_entries, '$.transitions')) as transitions,
    cast(json_extract(workflows_entries, '$.__v') as varchar) as v,
    cast(json_extract(workflows_entries, '$.endTime') as varchar) as ts_end,
    json_format(json_extract(workflows_entries, '$.context')) as context,
    dt
from json_entries
;