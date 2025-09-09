SELECT
    -- ids
    id,
    candidate_id AS id_candidate,
    application_id AS id_application,
    interview_step.id AS id_interview_step,
    submitted_by.id AS id_submitted_by,
    interviewer.id AS id_interviewer,
    -- text fields
    interview AS interview_name,
    interview_step.name AS interview_step_name,
    overall_recommendation,
    submitted_by.name AS submitted_by_name,
    interviewer.name AS interviewer_name,
    -- timestamps
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    CAST(interviewed_at AS TIMESTAMP) AS ts_interviewed,
    CAST(submitted_at AS TIMESTAMP) AS ts_submitted,
    NOW() AS ts_load,
    -- arrays
    attributes,
    questions,
    ratings.mixed AS ratings_mixed,
    ratings.no AS ratings_no,
    ratings.strong_yes AS ratings_strong_yes,
    ratings.yes AS ratings_yes,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.scorecards
WHERE
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1