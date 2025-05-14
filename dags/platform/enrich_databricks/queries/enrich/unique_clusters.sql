SELECT
    c.cluster_id AS id_cluster,
    c.workspace_id AS id_organization,
    c.driver_instance_pool_id AS id_driver_instance_pool,
    c.worker_instance_pool_id AS id_worker_instance_pool,
    CASE
        WHEN c.workspace_id = '4531937035440038' THEN 'QuintoAndar'
        WHEN c.workspace_id = '4033397625841925' THEN 'Forno'
        WHEN c.workspace_id = '6170817193817' THEN 'Prod'
    END AS workspace_name,
    c.cluster_name,
    CASE
        WHEN c.cluster_name LIKE 'bietlejuice%' OR c.cluster_name LIKE 'job-%'
          THEN NULLIF(REPLACE(REGEXP_EXTRACT(
            c.cluster_name,
            '(bietlejuice(?:\.|-)(?:(?:\w|\.)+))_(?:manual|scheduled|mediator_trig)'
          ), '-', '.'), '')
    END AS bietlejuice_dag_name,
    CASE
        WHEN c.tags.ResourceClass = 'SingleNode' THEN 'Single Node'
        ELSE 'Standard'
    END AS cluster_type,
    REPLACE(c.dbr_version, '-photon-', '-') AS spark_version,
    CASE
        WHEN c.dbr_version LIKE '%-photon-%' THEN 'PHOTON' ELSE 'STANDARD'
    END AS runtime_engine,
    TO_JSON(c.init_scripts) AS init_scripts,
    TO_JSON(c.tags) AS custom_tags,
    c.driver_node_type,
    c.worker_node_type AS node_type,
    FROM_JSON(TO_JSON(c.aws_attributes), 'map<string, string>') AS aws_attributes,
    ip_driver.instance_pool_name AS driver_instance_pool_name,
    ip_worker.instance_pool_name AS worker_instance_pool_name,
    c.worker_count::INT AS num_workers,
    TO_JSON(STRUCT(
        c.min_autoscale_workers AS min_workers,
        c.max_autoscale_workers AS max_workers
    )) AS autoscale,
    c.auto_termination_minutes::INT AS auto_termination_minutes,
    c.enable_elastic_disk AS is_elastic_disk_enabled,
    c.cluster_source = 'JOB' AS is_automated,
    c.change_time AS ts_updated,
    c.delete_time AS ts_deleted
FROM
    `system`.compute.clusters AS c
LEFT JOIN
    datalake_databricks.instance_pools AS ip_driver
        ON c.driver_instance_pool_id = ip_driver.id_instance_pool
LEFT JOIN
    datalake_databricks.instance_pools AS ip_worker
        ON c.worker_instance_pool_id = ip_worker.id_instance_pool
WHERE
    change_date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY cluster_id ORDER BY change_time DESC) = 1
