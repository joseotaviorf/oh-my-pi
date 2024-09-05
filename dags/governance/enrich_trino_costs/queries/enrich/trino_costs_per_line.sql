WITH email_line AS (
    SELECT
        oc.work_email,
        ccd.line
    FROM
        datalake_people_public.org_chart AS oc
    LEFT JOIN
        datalake_gsheets_clean.cost_center_directory AS ccd
            ON  oc.cost_center_name = ccd.cost_center
),
processed_data_per_line_per_day AS (
    SELECT
        DATE(created_time) AS created_date,
        el.line,
        SUM((processed_input_data_bytes) / (1024 * 1024 * 1024)) AS total_processed_input_data_gbytes
    FROM
        data_platform_metrics.trino_query_log_events_metrics_clean_batch AS tqlemcb
    LEFT JOIN
        email_line AS el
            ON  get_json_object(tqlemcb.session, "$.user" ) = el.work_email
    WHERE
        querytype = 'SELECT'
        AND state IN ('FINISHED', 'FAILED')
        AND MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
    GROUP BY
        DATE(created_time),
        el.line
),
total_platform_cost_per_day AS (
    SELECT
        DATE(line_item_usage_start_date) AS created_date,
        SUM(line_item_unblended_cost) AS total_cost_in_dollars
    FROM
        cost_usage_reports.aws_costs_new
    WHERE
        COALESCE(resource_tags_aws_autoscaling_group_name, resource_tags_user_app) LIKE '%trino%'
        AND MAKE_DATE(year, month, DAY(line_item_usage_start_date)) BETWEEN "{load_start_date}" AND "{load_end_date}"
    GROUP BY
        DATE(line_item_usage_start_date)
)
SELECT
    d.year_quarter,
    d.quarter,
    pdlpd.line,
    pdlpd.total_processed_input_data_gbytes,
    tpcpd.total_cost_in_dollars * (pdlpd.total_processed_input_data_gbytes / SUM(pdlpd.total_processed_input_data_gbytes) OVER (PARTITION BY pdlpd.created_date)) AS proportional_cost_in_dollars,
    pdlpd.created_date AS dt_created,
    d.year,
    d.month,
    d.day
FROM
    processed_data_per_line_per_day AS pdlpd
LEFT JOIN
    total_platform_cost_per_day AS tpcpd
        ON pdlpd.created_date = tpcpd.created_date
LEFT JOIN
    dw_public.dim_date AS d
        ON pdlpd.created_date = d.date
