SELECT
    clusterId AS id_cluster,
    clusterOwnerUserId AS id_cluster_owner,
    workspaceId AS id_workspace,
    clusterName AS cluster_name,
    clusterNodeType AS cluster_node_type,
    clusterCustomTags AS cluster_custom_tags,
    clusterOwnerUserName AS cluster_owner_email,
    sku AS cluster_compute_type,
    tags,
    dbus,
    machineHours AS machine_hours,
    timestamp AS ts_execution,
    year,
    month,
    day
FROM
    datalake_databricks_usage_raw.billable_usage
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
