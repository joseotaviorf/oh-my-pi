 WITH explode_answer_choices AS (
    SELECT
        id_question,
        EXPLODE(
            SPLIT(
                SUBSTRING(TRIM(answer_choices), 2, LENGTH(TRIM(answer_choices))-2)
            , "}}")
        ) AS answer_choices,
        dt_load,
        year,
        month,
        day
    FROM
        datalake_survicate_clean.survey_questions
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
),
format_answer_choices AS (
    SELECT
        id_question,
        CASE
            WHEN SUBSTRING(TRIM(answer_choices), 1, 1) = ","
                THEN CONCAT(SUBSTRING(TRIM(answer_choices), 2, LENGTH(TRIM(answer_choices))), "}}")
            ELSE CONCAT(TRIM(answer_choices), "}}")
        END AS answer_choices,
        dt_load,
        year,
        month,
        day
    FROM
        explode_answer_choices
    WHERE
        answer_choices IS NOT NULL
        AND TRIM(answer_choices) NOT IN ('', '[', ']')
)
SELECT
    GET_JSON_OBJECT(answer_choices, '$.id') AS id_answer_choice,
    id_question,
    GET_JSON_OBJECT(answer_choices, '$.content') AS answer_content,
    dt_load,
    year,
    month,
    day
FROM
    format_answer_choices