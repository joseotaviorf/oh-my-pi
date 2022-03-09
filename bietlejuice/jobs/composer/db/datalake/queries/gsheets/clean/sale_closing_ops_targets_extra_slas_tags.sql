SELECT
    tag_salesflow as salesflow_tag,
    INT(sla_extra) as extra_sla_days,
    metric_name
FROM
    datalake_gsheets_raw.sale_closing_ops_targets_extra_slas_tags