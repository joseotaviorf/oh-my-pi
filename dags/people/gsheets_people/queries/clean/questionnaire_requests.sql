SELECT
    NULLIF(unique_id, '') AS survey_invite_id,
    NULLIF(survey_title, '') AS survey_title,
    NULLIF(requester, '') AS requester_email,
    NULLIF(team_members, '') AS team_members,
    NULLIF(survey_status, '') AS survey_status,
    NULLIF(report_status, '') AS report_status,
    CAST(NULLIF(invited, '') AS INT) AS invited_count,
    CAST(NULLIF(answered, '') AS INT) AS answered_count,
    TO_DATE(NULLIF(survey_start_date, ''), 'M/d/yyyy') AS dt_survey_started,
    TO_DATE(NULLIF(survey_end_date, ''), 'M/d/yyyy') AS dt_survey_ended,
    TO_TIMESTAMP(timestamp, 'M/d/yyyy HH:mm:ss') AS ts_requested,
    TO_TIMESTAMP(NULLIF(report_email_sent, ''), 'M/d/yyyy HH:mm:ss') AS ts_report_email_sent,
    NOW() AS ts_load
FROM
    datalake_gsheets_people_raw.questionnaire_requests
WHERE
    NULLIF(unique_id, '') IS NOT NULL
