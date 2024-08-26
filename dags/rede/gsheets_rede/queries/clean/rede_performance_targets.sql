SELECT
    NULLIF(mes, '') AS month,
    NULLIF(cluster, '') AS cluster,
    NULLIF(flow, '') AS flow,
    NULLIF(type, '') AS metric_type,
    NULLIF(account_manager, '') AS account_manager,
    NULLIF(target, '') AS metric_target
FROM
    datalake_gsheets_raw.rede_performance_targets