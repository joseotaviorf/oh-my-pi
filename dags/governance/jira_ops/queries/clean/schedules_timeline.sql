SELECT
    schedule_id AS id_schedule,
    finalTimeline AS final_timeline,
    baseTimeline AS base_timeline,
    dt_load,
    TIMESTAMP(startDate) AS ts_started,
    TIMESTAMP(endDate) AS ts_ended,
    year,
    month,
    day
FROM
    datalake_jira_ops_raw.schedules_timeline
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
