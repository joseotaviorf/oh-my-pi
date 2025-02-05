WITH explode_parse_url AS (
  SELECT
    id_response,
    id_survey,
    id_respondent,
    sr.response_url,
    sr.survey_name
  FROM
    datalake_survicate.survey_responses AS sr
  WHERE
    sr.id_survey IN
    (
      'a514a5d6fe646931',
      '01176589bb5ad239',
      'f28163ea321f7cab'
    )
    AND sr.dt_load BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
,zendesk_tickets AS (
  SELECT DISTINCT
    id_response,
    id_survey,
    id_respondent,
    REGEXP_EXTRACT(response_url,'id=([0-9]+)') AS id_ticket,
    REGEXP_EXTRACT(response_url,'email=([^&]+)') AS respondent_email,
    survey_name
  FROM
    explode_parse_url
)
, final_df as (
SELECT
  rc.id_response AS id_answer,
  sr.id_survey,
  sr.id_respondent,
  MAX(sr.id_ticket) AS id_ticket,
  MAX(sr.respondent_email) AS respondent_email,
  sr.survey_name,
  CASE
    WHEN sr.id_survey = '01176589bb5ad239' THEN "owner"
    WHEN sr.id_survey = 'a514a5d6fe646931' THEN "tenant"
  END AS respondent_type,
  'repairs' AS service_type,
  'offboarding' AS service_context,
  'survicate' AS source_name,
  CAST(
    COLLECT_LIST(
      CASE
        WHEN rc.id_question IN
          (
            1852448,
            1852462,
            2864548,
            2864549
          )
        THEN rc.answer_content
      END
    ) AS STRING
  ) AS improvement_tags,
  MAX(
    CASE
      WHEN rc.id_question IN
        (
          1852449,
          1852463,
          2864550
        )
      THEN rc.answer_content
    END
  ) AS respondent_comments,
  CAST(
    MAX(
      CASE
        WHEN rc.id_question IN (1852451, 1852461) THEN rc.answer_content
        WHEN rc.id_question = '2864547' AND rc.answer_content = 'Extremely happy' THEN  5
        WHEN rc.id_question = '2864547' AND rc.answer_content = 'Happy' THEN  4
        WHEN rc.id_question = '2864547' AND rc.answer_content = 'Neutral' THEN  3
        WHEN rc.id_question = '2864547' AND rc.answer_content = 'Unsatisfied' THEN  2
        WHEN rc.id_question = '2864547' AND rc.answer_content = 'Extremely unsatisfied' THEN  1
      END
    ) AS INT
  ) AS satisfaction_score,
  "satisfaction evaluation" AS score_description,
  CAST(
    MAX(
      CASE
        WHEN rc.id_question IN (1852447, 1852460)
        THEN rc.answer_content
      END
    ) AS INT
  ) AS secondary_satisfaction_score,
  "satisfaction between parties involved" AS secondary_score_description,
  rc.ts_collected AS ts_submitted,
  rc.dt_load,
  rc.year,
  rc.month,
  rc.day
FROM
    datalake_survicate.response_content AS rc
JOIN
  zendesk_tickets AS sr
    ON sr.id_response = rc.id_response
WHERE
  rc.dt_load BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY
  ALL
)
SELECT
  *
FROM
  final_df
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_answer ORDER BY dt_load DESC) = 1