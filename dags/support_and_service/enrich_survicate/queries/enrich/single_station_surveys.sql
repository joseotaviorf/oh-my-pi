WITH emails as (
  SELECT
    get_json_object(regexp_replace(sr.respondent, "'", '"'), '$.uuid') AS respondent_uuid,
    id_survey,
    value as email
  FROM 
    datalake_survicate_clean.survey_responses sr
  LEFT JOIN datalake_survicate_clean.respondent_attributes attr
    ON get_json_object(regexp_replace(sr.respondent, "'", '"'), '$.uuid') = attr.respondent_uuid
    WHERE name = 'email'
), user_id as (
  SELECT
    get_json_object(regexp_replace(sr.respondent, "'", '"'), '$.uuid') AS respondent_uuid,
    id_survey,
    value as user_id
  FROM 
    datalake_survicate_clean.survey_responses sr
  LEFT JOIN datalake_survicate_clean.respondent_attributes attr
    ON get_json_object(regexp_replace(sr.respondent, "'", '"'), '$.uuid') = attr.respondent_uuid
    WHERE name = 'user_id'
)
SELECT
    sr.id_response,
    sr.id_survey,
    sr.id_respondent,
    u.user_id,
    e.email,
    sr.survey_name,
    'analyst' AS respondent_type,
    'magic_link_2' AS service_type,
    'single_station' AS service_context,
    'survicate' AS source_name,
    MAX(CAST(
        CASE 
            WHEN rc.id_question IN (2714051, 2718067, 2720689, 2720694) 
            THEN rc.answer_content
        END AS INT
    )) AS facility_satisfaction,
    MAX(CAST(
        CASE 
            WHEN rc.id_question IN (2714054, 2718068, 2720690, 2720695) 
            THEN rc.answer_content
        END AS INT
    )) AS time_satisfaction,
    MAX(CAST(
        CASE 
            WHEN rc.id_question IN (2714057, 2718069, 2720691, 2720696) 
            THEN rc.answer_content
        END AS INT
    )) AS support_satisfaction,
    MAX(
        CASE 
            WHEN rc.id_question IN (2714059, 2718070, 2720692, 2720697) 
            THEN rc.answer_content
        END
    ) AS improvements_suggestions,
    rc.ts_collected AS ts_submitted,
    rc.dt_load AS dt_load,
    YEAR(rc.dt_load)AS year,
    MONTH(rc.dt_load) AS month,
    DAY(rc.dt_load) AS day
FROM
  datalake_survicate.survey_responses AS sr 
JOIN 
  datalake_survicate.response_content AS rc 
  ON sr.id_response = rc.id_response 
LEFT JOIN emails AS e
  ON e.respondent_uuid = sr.id_respondent
LEFT JOIN user_id as u
  ON u.respondent_uuid = sr.id_respondent
WHERE sr.id_survey IN ('775741557ef98468','9fa10adff80551f6','74c8f0608123f05d','9efcef20c637ee47','739bb49c771b2806') 
AND DATE(rc.dt_load) BETWEEN DATE('{load_start_date}') AND DATE('{load_start_date}')
GROUP BY
    ALL