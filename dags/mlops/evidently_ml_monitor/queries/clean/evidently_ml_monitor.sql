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
        AND dt BETWEEN '{load_start_date}' AND '{load_end_date}'
),
deduped AS (
    SELECT
        run_id,
        metric_name,
        max_by(job_name, timestamp) AS job_name,
        max_by(json_data, timestamp) AS json_data,
        max_by(model_uri, timestamp) AS model_uri,
        max_by(execution_context_s3_path, timestamp) AS execution_context_s3_path,
        MAX(timestamp) AS timestamp
    FROM
        filtered
    GROUP BY
        run_id,
        metric_name
),
aggregated AS (
    SELECT
        run_id,
        ANY_VALUE(job_name) AS job_name,
        ANY_VALUE(model_uri) AS model_uri,
        ANY_VALUE(execution_context_s3_path) AS execution_context_s3_path,
        MAX(timestamp) AS ts_report,
        map_from_entries(
            collect_list(
                struct(
                    metric_name AS key,
                    json_data AS value
                )
            )
        ) AS metric_reports
    FROM
        deduped
    GROUP BY
        run_id
)
SELECT
    run_id,
    job_name,
    model_uri,
    regexp_extract(model_uri, '^models:/(.+)/([^/]+)$', 1) AS model_registry_path,
    regexp_extract(model_uri, '^models:/(.+)/([^/]+)$', 2) AS model_version,
    execution_context_s3_path,
    CAST(ts_report AS TIMESTAMP) AS ts_report,
    metric_reports
FROM
    aggregated
