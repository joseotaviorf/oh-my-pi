WITH explode_questions AS (
    SELECT
        response_uuid,
        EXPLODE(
            SPLIT(
                REPLACE(REPLACE(REPLACE(
                    SUBSTRING(TRIM(answers), 2, length(TRIM(answers))-2)
                    , 'True', "'True'"), 'False', "'False'"), 'None', "'None'"
                )
            , "'question_id':")
        ) AS answer,
        ts_collected,
        dt_load,
        year,
        month,
        day
    FROM
        datalake_survicate_clean.survey_responses sr
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
),
format_questions AS (
    SELECT
        response_uuid,
        CASE
            WHEN SUBSTRING(SUBSTRING(TRIM(answer), -1), -1) = "{{"
                THEN CONCAT("{{'question_id':", SUBSTRING(TRIM(answer), 1, length(TRIM(answer))-3))
            ELSE CONCAT("{{'question_id':", TRIM(answer))
        END AS answer,
        ts_collected,
        dt_load,
        year,
        month,
        day
    FROM
        explode_questions
    WHERE
        answer IS NOT NULL AND TRIM(answer) NOT IN ('', '[', ']', '{{', '}}')
),
extract_questions_info AS (
    SELECT
        response_uuid,
        GET_JSON_OBJECT(answer, "$.question_id") AS id_question,
        GET_JSON_OBJECT(answer, "$.question_type") AS question_type,
        COALESCE(
            GET_JSON_OBJECT(answer, "$.answer"),
            GET_JSON_OBJECT(answer, "$.fields"),
            GET_JSON_OBJECT(answer, "$.answers")
        ) AS answer,
        GET_JSON_OBJECT(answer, "$.question_type") IN ('form', 'multiple') AS has_multiple_answer,
        GET_JSON_OBJECT(answer, "$.action_performed") IS TRUE AS is_action_performed,
        ts_collected,
        dt_load,
        year,
        month,
        day
    FROM
        format_questions
),
explode_multiple_answer AS (
    SELECT
        response_uuid,
        id_question,
        question_type,
        EXPLODE(
            CASE
                WHEN question_type = 'form'
                    THEN SPLIT(
                        SUBSTRING(TRIM(answer), 2, LENGTH(TRIM(answer))-2)
                    , '"type":')
                ELSE SPLIT(
                    SUBSTRING(TRIM(answer), 2, LENGTH(TRIM(answer))-2)
                , '"id":')
            END
        ) AS answer,
        has_multiple_answer,
        is_action_performed,
        ts_collected,
        dt_load,
        year,
        month,
        day
    FROM
        extract_questions_info
    WHERE
        has_multiple_answer IS TRUE
),
format_multiple_answers AS (
    SELECT
        response_uuid,
        id_question,
        question_type,
        CASE
            WHEN SUBSTRING(SUBSTRING(TRIM(answer), -1), -1) = "{{" AND question_type = 'form'
                THEN CONCAT('{{"type":', SUBSTRING(TRIM(answer), 1, length(TRIM(answer))-2))
            WHEN SUBSTRING(SUBSTRING(TRIM(answer), -1), -1) = "{{"
                THEN CONCAT('{{"id":', SUBSTRING(TRIM(answer), 1, length(TRIM(answer))-2))
            WHEN SUBSTRING(SUBSTRING(TRIM(answer), -1), -1) <> "{{" AND question_type = 'form'
                THEN CONCAT('{{"type":', TRIM(answer))
            ELSE CONCAT('{{"id":', TRIM(answer))
        END AS answer,
        has_multiple_answer,
        is_action_performed,
        ts_collected,
        dt_load,
        year,
        month,
        day
    FROM
        explode_multiple_answer
    WHERE
        answer IS NOT NULL
        AND TRIM(answer) NOT IN ('', '[', ']', '{{', '}}')
),
union_answers AS (
    SELECT
        *
    FROM
        extract_questions_info
    WHERE
        has_multiple_answer IS FALSE
    UNION ALL
    SELECT
        *
    FROM
        format_multiple_answers
)
SELECT
    response_uuid AS id_response,
    id_question,
    GET_JSON_OBJECT(answer, "$.id") AS id_answer,
    question_type,
    COALESCE(
        GET_JSON_OBJECT(answer, "$.content"),
        answer
    ) AS answer_content,
    CASE
        WHEN TRIM(GET_JSON_OBJECT(answer, "$.comment")) IN ('', 'None', 'null') THEN NULL
        ELSE GET_JSON_OBJECT(answer, "$.comment")
    END AS answer_comment,
    GET_JSON_OBJECT(answer, "$.type") AS field_type,
    is_action_performed,
    ts_collected,
    dt_load,
    year,
    month,
    day
FROM
    union_answers