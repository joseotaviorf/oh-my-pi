drop table if exists datalake_clean.crm_task_resolution_history;
create external table if not exists datalake_clean.crm_task_resolution_history (
    id_task string,
    id_action string,
    id_assignee string,
    id_user_action string,
    id_house string,
    id_rent_flow string,
    id_origin string,
    id_opened_by string,
    id_tenant string,
    id_negotiation string,
    id_manager string,
    id_owner string,
    id_receiver string,
    type string,
    action_user_name string,
    action_type string,
    action_reason string,
    task_status string,
    resolved string,
    tags string,
    metadata string,
    score_factor string,
    receiver_name string,
    comment string,
    score string,
    origin string,
    receiver_type string,
    description string,
    phase string,
    analyst_started_list string,
    subject string,
    visit_fup string,
    v string,
    task_user_resolve_hours string,
    ts_action string,
    ts_previous_action string,
    ts_next_action string,
    ts_created string,
    ts_start string,
    ts_completed string,
    ts_visit string,
    ts_silenced_until string,
    ts_origin string,
    ts_fup string
)
partitioned by (
    dt string
)
stored as parquet
location 's3://5a-datalake/clean/crm/task_resolution_history/'
;
