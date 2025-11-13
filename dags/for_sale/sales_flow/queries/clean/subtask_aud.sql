SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    task_id AS id_task,
    task_id_mod AS mod_id_task,
    label,
    label_mod AS mod_label,
    type,
    type_mod AS mod_type,
    target,
    target_mod AS mod_target,
    deadline,
    deadline_mod AS mod_deadline,
    activation_trigger,
    activation_trigger_mod AS mod_activation_trigger,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.subtask_aud
