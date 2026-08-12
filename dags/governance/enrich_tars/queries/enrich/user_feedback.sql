-- User feedback (open text + 1-5 Likert score) from the Vector user_feedback event,
-- emitted once per completed feedback interview by the tars-feedback skill.
SELECT
    CONCAT('feedback-', id_session, '-', CAST(UNIX_TIMESTAMP(ts_event) AS STRING)) AS id_feedback,
    id_session,
    session_source,
    user_slug,
    feedback_text,
    likert_score,
    likert_label,
    status,
    ts_event AS ts_feedback,
    dt_event AS dt_feedback,
    year,
    month,
    day
FROM
    datalake_tars_clean.vector_logs
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
    AND "{load_end_date}"
    AND event_type = 'user_feedback'
