SELECT
    cluster_id AS id_cluster,
    organization_id AS id_organization,
    driver_instance_pool_id AS id_driver_instance_pool,
    instance_pool_id AS id_worker_instance_pool,
    cluster_name,
    CASE
        WHEN cluster_name LIKE 'bietlejuice%' OR cluster_name LIKE 'job-%'
          THEN NULLIF(REPLACE(REGEXP_EXTRACT(
            cluster_name,
            '(bietlejuice(?:\.|-)(?:(?:\w|\.)+))_(?:manual|scheduled|mediator_trig)'
          ), '-', '.'), '')
    END AS bietlejuice_dag_name,
    cluster_type,
    spark_version,
    runtime_engine,
    init_scripts,
    custom_tags,
    driver_node_type,
    node_type,
    aws_attributes,
    driver_instance_pool_name,
    instance_pool_name AS worker_instance_pool_name,
    num_workers,
    autoscale,
    auto_termination_minutes,
    enable_elastic_disk AS is_elastic_disk_enabled,
    is_automated,
    `timestamp` AS ts_updated
FROM
    overwatch.`cluster`
WHERE
    `date` BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY cluster_id ORDER BY unixTimeMS DESC) = 1
