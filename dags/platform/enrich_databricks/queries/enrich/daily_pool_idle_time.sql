/*
This query results in 1 row per combination of (node_type, pool_name, dt_cluster_run). This means we're getting daily metrics of:
- Each instance pool
- Each node type that isn't in a pool

The goal is to compare the idle time of instances in a pool vs not in a pool, to get a sense of how efficient cluster pools are.

Important: the idle time is not very accurate, but an approximation. Overwatch's reported usage time doesn't seem to match with the aws_costs table
very well.
*/

WITH databricks_aux AS (
    SELECT
        id_cluster,
        driver_node_type AS node_type,
        driver_instance_pool_name AS pool_name,
        1 AS num_nodes,
        total_seconds_uptime AS total_instance_usage_seconds,
        dt_cluster_run
    FROM
        datalake_databricks.daily_clusters
    WHERE
        dt_cluster_run BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
    UNION ALL
    SELECT
        id_cluster,
        node_type,
        worker_instance_pool_name AS pool_name,
        avg_target_num_workers AS num_nodes,
        total_worker_instance_usage_seconds AS total_instance_usage_seconds,
        dt_cluster_run
    FROM
        datalake_databricks.daily_clusters
    WHERE
        dt_cluster_run BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
),
databricks AS (
    SELECT
        id_cluster,
        node_type,
        COALESCE(pool_name, 'No pool') AS pool_name,
        SUM(num_nodes) AS num_nodes,
        SUM(total_instance_usage_seconds) AS total_instance_usage_seconds,
        dt_cluster_run
    FROM
        databricks_aux
    GROUP BY
        id_cluster,
        pool_name,
        node_type,
        dt_cluster_run
),
aws AS (
    SELECT
        resource_tags_user_cluster_id AS id_cluster,
        product_instance_type AS node_type,
        CASE -- We're standardizing that every cluster pool will add a tag "application" with the value `pool:<pool_name>`
            WHEN resource_tags_user_app LIKE 'pool:%' THEN SUBSTRING(resource_tags_user_app, 6)
        END AS pool_name,
        SUM(line_item_usage_amount) * 3600 AS compute_seconds_aws,
        COUNT(DISTINCT line_item_resource_id) AS num_provisioned_instances,
        DATE(line_item_usage_start_date) AS dt_cluster_run
    FROM
        cost_usage_reports.aws_costs_new
    WHERE
        -- We first run this filter with the partition columns to speed up the query
        MAKE_DATE(year, month, 1) BETWEEN DATE_TRUNC('MONTH', DATE("{load_start_date}"))
        AND DATE_TRUNC('MONTH', DATE("{load_end_date}"))
        AND product_product_family = 'Compute Instance'
        AND lower(resource_tags_user_vendor) = 'databricks'
        -- Only then we get specific with the date
        AND DATE(line_item_usage_start_date) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
    GROUP BY
        id_cluster,
        node_type,
        pool_name,
        dt_cluster_run
),
metrics_without_pool AS (
    SELECT
        aws.node_type,
        NULL AS pool_name,
        SUM(databricks.num_nodes) AS num_nodes,
        SUM(aws.compute_seconds_aws) AS total_aws_compute_seconds,
        SUM(databricks.total_instance_usage_seconds) AS total_databricks_compute_seconds,
        SUM(aws.compute_seconds_aws - databricks.total_instance_usage_seconds) AS total_aws_idle_time_in_seconds,
        SUM(aws.compute_seconds_aws - databricks.total_instance_usage_seconds) / SUM(databricks.num_nodes) AS avg_idle_time_per_instance_in_seconds,
        databricks.dt_cluster_run
    FROM
        databricks
    JOIN
        aws
            ON databricks.id_cluster = aws.id_cluster
            AND databricks.node_type = aws.node_type
            AND databricks.dt_cluster_run = aws.dt_cluster_run
    WHERE
        -- Removing outliers due to edge cases, like extra AWS time charged in reserved instances
        aws.compute_seconds_aws - databricks.total_instance_usage_seconds BETWEEN 0 AND 3600
    GROUP BY
        aws.node_type,
        databricks.dt_cluster_run
),
metrics_with_pool AS (
    SELECT
        aws.node_type,
        aws.pool_name,
        -- In this CTE we're using any_value because the join below is 1:N
        -- There is going to be a single row in "aws" for each pool, but there might be multiple rows
        -- in "databricks" using the same pool. We're using ANY_VALUE for AWS and SUM for databricks
        ANY_VALUE(aws.num_provisioned_instances) AS num_nodes,
        ANY_VALUE(aws.compute_seconds_aws) AS total_aws_compute_seconds,
        SUM(databricks.total_instance_usage_seconds) AS total_databricks_compute_seconds,
        ANY_VALUE(aws.compute_seconds_aws) - SUM(databricks.total_instance_usage_seconds) AS total_aws_idle_time_in_seconds,
        (ANY_VALUE(aws.compute_seconds_aws) - SUM(databricks.total_instance_usage_seconds)) / ANY_VALUE(aws.num_provisioned_instances) AS avg_idle_time_per_instance_in_seconds,
        aws.dt_cluster_run
    FROM
        aws
    LEFT JOIN
        databricks
            ON databricks.node_type = aws.node_type
            AND databricks.pool_name = aws.pool_name
            AND databricks.dt_cluster_run = aws.dt_cluster_run
    WHERE
        aws.pool_name IS NOT NULL
    GROUP BY
        aws.node_type,
        aws.pool_name,
        aws.dt_cluster_run
)
SELECT *
FROM
    metrics_with_pool
UNION ALL
SELECT *
FROM
    metrics_without_pool
