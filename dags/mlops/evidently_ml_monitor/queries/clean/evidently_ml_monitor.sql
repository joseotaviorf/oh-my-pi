WITH filtered AS (
    SELECT
        run_id,
        job_name,
        metric_name,
        json_data,
        model_uri,
        execution_context_s3_path,
        timestamp
    FROM
        datalake_evidently_ml_monitor_raw.evidently_ml_monitor
    WHERE
        json_data IS NOT NULL
        AND metric_name IS NOT NULL
        AND job_name IS NOT NULL
        AND dt >= '{load_start_date}'
        AND dt < '{load_end_date}'
        AND ('{job_name}' = '' OR job_name = '{job_name}')
),
deduped AS (
    SELECT
        run_id,
        metric_name AS suite_name,
        MAX_BY(job_name, timestamp) AS job_name,
        MAX_BY(json_data, timestamp) AS json_data,
        MAX_BY(model_uri, timestamp) AS model_uri,
        MAX_BY(execution_context_s3_path, timestamp) AS execution_context_s3_path,
        MAX(timestamp) AS ts_report
    FROM
        filtered
    GROUP BY
        run_id,
        metric_name
)
SELECT
    d.run_id,
    d.job_name,
    d.suite_name,
    e.metric_id,
    d.model_uri,
    REGEXP_EXTRACT(d.model_uri, '^models:/(.+)/([^/]+)$', 1) AS model_registry_path,
    REGEXP_EXTRACT(d.model_uri, '^models:/(.+)/([^/]+)$', 2) AS model_version,
    d.execution_context_s3_path,
    CAST(d.ts_report AS TIMESTAMP) AS ts_report,
    GET_JSON_OBJECT(
        d.json_data,
        CONCAT('$.metric_results["', e.metric_id, '"]')
    ) AS metric_result_json
FROM
    deduped AS d
    LATERAL VIEW EXPLODE(
        JSON_OBJECT_KEYS(
            GET_JSON_OBJECT(d.json_data, '$.metric_results')
        )
    ) e AS metric_id
WHERE
    e.metric_id IS NOT NULL
