SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    label,
    label_mod AS mod_label,
    subject,
    subject_mod AS mod_subject,
    source,
    source_mod AS mod_source,
    source_related_id AS id_source_related,
    source_related_id_mod AS mod_id_source_related,
    task_trigger,
    task_trigger_mod AS mod_task_trigger,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.task_aud
