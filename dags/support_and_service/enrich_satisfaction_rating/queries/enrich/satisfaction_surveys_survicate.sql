SELECT
    iss.id_answer,
    iss.id_survey,
    iss.id_contract,
    NULL AS id_ticket,
    iss.id_respondent,
    NULL AS respondent_email,
    iss.respondent_type,
    iss.service_type,
    iss.service_context,
    iss.source_name,
    iss.improvement_tags,
    iss.respondent_comments,
    iss.satisfaction_score,
    iss.score_description,
    iss.secondary_satisfaction_score,
    iss.secondary_score_description,
    iss.custom_attributes,
    iss.ts_first_seen,
    iss.ts_submitted,
    iss.year,
    iss.month,
    iss.day
FROM
    datalake_survicate.inspections_surveys AS iss
WHERE
    iss.year = {year}
    AND iss.month = {month}
    AND iss.day = {day}
UNION ALL
SELECT
    rss.id_answer,
    rss.id_survey,
    NULL AS id_contract,
    rss.id_ticket,
    NULL AS id_respondent,
    rss.respondent_email,
    rss.respondent_type,
    rss.service_type,
    rss.service_context,
    rss.source_name,
    rss.improvement_tags,
    rss.respondent_comments,
    rss.satisfaction_score,
    rss.score_description,
    rss.secondary_satisfaction_score,
    rss.secondary_score_description,
    rss.custom_attributes,
    rss.ts_first_seen,
    rss.ts_submitted,
    rss.year,
    rss.month,
    rss.day
FROM
    datalake_survicate.repairs_surveys AS rss
WHERE
    rss.year = {year}
    AND rss.month = {month}
    AND rss.day = {day}
UNION ALL
SELECT
    lss.id_answer,
    lss.id_survey,
    NULL AS id_contract,
    NULL AS id_ticket,
    NULL AS id_respondent,
    NULL AS respondent_email,
    lss.respondent_type,
    lss.service_type,
    lss.service_context,
    lss.source_name,
    lss.improvement_tags,
    lss.respondent_comments,
    lss.satisfaction_score,
    lss.score_description,
    NULL AS secondary_satisfaction_score,
    NULL AS secondary_score_description,
    lss.custom_attributes,
    lss.ts_first_seen,
    lss.ts_submitted,
    lss.year,
    lss.month,
    lss.day
FROM
    datalake_survicate.lockbox_surveys AS lss
WHERE
    lss.year = {year}
    AND lss.month = {month}
    AND lss.day = {day}
UNION ALL
SELECT
    sss.id_answer,
    sss.id_survey,
    sss.id_contract,
    NULL AS id_ticket,
    NULL AS id_respondent,
    NULL AS respondent_email,
    sss.respondent_type,
    sss.service_type,
    sss.service_context,
    sss.source_name,
    sss.improvement_tags,
    sss.respondent_comments,
    sss.satisfaction_score,
    sss.score_description,
    NULL AS secondary_satisfaction_score,
    NULL AS secondary_score_description,
    sss.custom_attributes,
    sss.ts_first_seen,
    sss.ts_submitted,
    sss.year,
    sss.month,
    sss.day
FROM
    datalake_survicate.scheduling_surveys AS sss
WHERE
    sss.year = {year}
    AND sss.month = {month}
    AND sss.day = {day}
UNION ALL
SELECT
    kss.id_answer,
    kss.id_survey,
    kss.id_contract,
    kss.id_ticket,
    NULL AS id_respondent,
    kss.email AS respondent_email,
    NULL AS respondent_type,
    kss.service_type,
    kss.survey_type AS service_context,
    kss.survey_source AS source_name,
    kss.improvement_tags,
    kss.user_comment AS respondent_comments,
    kss.satisfaction_rating AS satisfaction_score,
    kss.score_description,
    NULL AS secondary_satisfaction_score,
    NULL AS secondary_score_description,
    kss.custom_attributes,
    kss.ts_first_seen,
    kss.ts_first_response AS ts_submitted,
    kss.year,
    kss.month,
    kss.day
FROM
    datalake_survicate.keys_surveys AS kss
WHERE
    kss.survey_source = 'survicate'
    AND kss.year = {year}
    AND kss.month = {month}
    AND kss.day = {day}
UNION ALL
SELECT
    pss.id_response AS id_answer,
    pss.id_survey,
    NULL AS id_contract,
    NULL AS id_ticket,
    pss.id_owner AS id_respondent,
    NULL AS respondent_email,
    LOWER(pss.respondent_type) AS respondent_type,
    pss.service_type,
    NULL AS service_context,
    pss.survey_source AS source_name,
    pss.improvement_tags,
    pss.user_comment AS respondent_comments,
    pss.satisfaction_rating AS satisfaction_score,
    pss.score_description,
    NULL AS secondary_satisfaction_score,
    NULL AS secondary_score_description,
    pss.custom_attributes,
    pss.ts_first_seen,
    pss.ts_first_response AS ts_submitted,
    pss.year,
    pss.month,
    pss.day
FROM
    datalake_survicate.photo_surveys AS pss
WHERE
    pss.year = {year}
    AND pss.month = {month}
    AND pss.day = {day}