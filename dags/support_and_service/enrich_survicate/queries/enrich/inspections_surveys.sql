WITH parse_url_format AS (
    SELECT
        sr.id_survey,
        sr.id_respondent,
        sr.id_response,
        CASE
            WHEN SIZE(SPLIT(sr.response_url, '&')) = 1 THEN CONCAT(
                "https://survey.survicate.com/",
                sr.id_survey,
                "/?",
                REPLACE(
                    SUBSTRING(
                        TRIM(SPLIT(response_url, '/') [4]),
                        2,
                        length(TRIM(SPLIT(response_url, '/') [4]))
                    ),
                    '?',
                    '&'
                )
            )
            ELSE sr.response_url
        END AS response_url
    FROM
        datalake_survicate.survey_responses AS sr
    WHERE
        sr.id_survey IN ('00f46ff66c2ff389', '9d64bf0e2f6faa48', 'ccecd6dbe925b337', '29d847ff4d17cc18')
        AND sr.year = {year}
        AND sr.month = {month}
        AND sr.day = {day}
)
SELECT
    rc.id_response AS id_answer,
    sr.id_survey,
    PARSE_URL(sr.response_url, 'QUERY', 'contractid') AS id_contract,
    PARSE_URL(sr.response_url, 'QUERY', 'inspectionId') AS id_inspection,
    c.id_user AS id_respondent,
    sr.id_respondent AS respondent_uuid,
    rc.survey_name,
    CASE
        WHEN sr.id_survey IN ('00f46ff66c2ff389', '29d847ff4d17cc18') THEN 'owner'
        WHEN sr.id_survey IN ('9d64bf0e2f6faa48', 'ccecd6dbe925b337') THEN 'tenant'
    END AS respondent_type,
    'inspections' AS service_type,
    CASE
        WHEN sr.id_survey IN ('00f46ff66c2ff389', '9d64bf0e2f6faa48') THEN 'offboarding'
        WHEN sr.id_survey IN ('ccecd6dbe925b337', '29d847ff4d17cc18') THEN 'onboarding'
    END AS service_context,
    'survicate' AS source_name,
    CAST(COLLECT_LIST(rc.answer_content) FILTER (WHERE rc.id_question IN (1869883, 1926516, 2251569, 2271245)) AS STRING) AS improvement_tags,
    LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1869884, 1926532, 2251570, 2271246)) AS respondent_comments,
    CAST(LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1835806, 1926509, 2271843, 2271243)) AS INT) AS satisfaction_score,
    "satisfaction evaluation" AS score_description,
    CAST(LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1835786, 2271244)) AS INT) AS secondary_satisfaction_score,
    "house satisfaction" AS secondary_score_description,
    rc.ts_collected AS ts_submitted,
    rc.dt_load,
    rc.year,
    rc.month,
    rc.day
FROM
    datalake_survicate.response_content AS rc
JOIN
    parse_url_format AS sr
        ON sr.id_response = rc.id_response
LEFT JOIN
    datalake_ebdb_clean.contract AS c
        ON c.id = PARSE_URL(sr.response_url, 'QUERY', 'contractid')
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 17, 18, 19, 20, 21