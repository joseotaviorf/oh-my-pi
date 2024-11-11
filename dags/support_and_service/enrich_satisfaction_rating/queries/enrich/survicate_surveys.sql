WITH survicate_surveys AS (
    SELECT
        iss.id_answer,
        iss.id_survey,
        iss.id_contract,
        NULL AS id_ticket,
        iss.id_inspection AS id_origin,
        iss.id_respondent,
        NULL AS respondent_email,
        iss.respondent_type,
        iss.survey_name,
        iss.service_type,
        iss.service_context,
        iss.source_name,
        iss.improvement_tags,
        iss.respondent_comments,
        iss.satisfaction_score,
        iss.score_description,
        iss.secondary_satisfaction_score,
        iss.secondary_score_description,
        iss.ts_submitted,
        iss.year,
        iss.month,
        iss.day
    FROM
        datalake_survicate.inspections_surveys AS iss
    WHERE
        MAKE_DATE(iss.year, iss.month, iss.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

    UNION ALL

    SELECT
        rss.id_answer,
        rss.id_survey,
        NULL AS id_contract,
        rss.id_ticket,
        NULL AS id_origin,
        NULL AS id_respondent,
        rss.respondent_email,
        rss.respondent_type,
        rss.survey_name,
        rss.service_type,
        rss.service_context,
        rss.source_name,
        rss.improvement_tags,
        rss.respondent_comments,
        rss.satisfaction_score,
        rss.score_description,
        rss.secondary_satisfaction_score,
        rss.secondary_score_description,
        rss.ts_submitted,
        rss.year,
        rss.month,
        rss.day
    FROM
        datalake_survicate.repairs_surveys AS rss
    WHERE
        MAKE_DATE(rss.year, rss.month, rss.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

    UNION ALL

    SELECT
        lss.id_answer,
        lss.id_survey,
        NULL AS id_contract,
        NULL AS id_ticket,
        NULL AS id_origin,
        NULL AS id_respondent,
        NULL AS respondent_email,
        lss.respondent_type,
        lss.survey_name,
        lss.service_type,
        lss.service_context,
        lss.source_name,
        lss.improvement_tags,
        lss.respondent_comments,
        lss.satisfaction_score,
        lss.score_description,
        NULL AS secondary_satisfaction_score,
        NULL AS secondary_score_description,
        lss.ts_submitted,
        lss.year,
        lss.month,
        lss.day
    FROM
        datalake_survicate.lockbox_surveys AS lss
    WHERE
        MAKE_DATE(lss.year, lss.month, lss.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

    UNION ALL

    SELECT
        sss.id_answer,
        sss.id_survey,
        sss.id_contract,
        NULL AS id_ticket,
        NULL AS id_origin,
        NULL AS id_respondent,
        NULL AS respondent_email,
        sss.respondent_type,
        sss.survey_name,
        sss.service_type,
        sss.service_context,
        sss.source_name,
        sss.improvement_tags,
        sss.respondent_comments,
        sss.satisfaction_score,
        sss.score_description,
        NULL AS secondary_satisfaction_score,
        NULL AS secondary_score_description,
        sss.ts_submitted,
        sss.year,
        sss.month,
        sss.day
    FROM
        datalake_survicate.scheduling_surveys AS sss
    WHERE
        MAKE_DATE(sss.year, sss.month, sss.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

    UNION ALL

    SELECT
        kss.id_answer,
        kss.id_survey,
        kss.id_contract,
        kss.id_ticket,
        NULL AS id_origin,
        NULL AS id_respondent,
        kss.email AS respondent_email,
        NULL AS respondent_type,
        kss.survey_name,
        kss.service_type,
        kss.survey_type AS service_context,
        kss.survey_source AS source_name,
        kss.improvement_tags,
        kss.user_comment AS respondent_comments,
        kss.satisfaction_rating AS satisfaction_score,
        kss.score_description,
        NULL AS secondary_satisfaction_score,
        NULL AS secondary_score_description,
        kss.ts_first_response AS ts_submitted,
        kss.year,
        kss.month,
        kss.day
    FROM
        datalake_survicate.keys_surveys AS kss
    WHERE
        kss.survey_source = 'survicate'
        AND MAKE_DATE(kss.year, kss.month, kss.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

    UNION ALL

    SELECT
        pss.id_response AS id_answer,
        pss.id_survey,
        NULL AS id_contract,
        NULL AS id_ticket,
        NULL AS id_origin,
        pss.id_owner AS id_respondent,
        NULL AS respondent_email,
        LOWER(pss.respondent_type) AS respondent_type,
        pss.survey_name,
        pss.service_type,
        pss.service_context,
        pss.survey_source AS source_name,
        pss.improvement_tags,
        pss.respondent_comments,
        pss.satisfaction_rating AS satisfaction_score,
        pss.score_description,
        NULL AS secondary_satisfaction_score,
        NULL AS secondary_score_description,
        pss.ts_first_response AS ts_submitted,
        pss.year,
        pss.month,
        pss.day
    FROM
        datalake_survicate.photo_surveys AS pss
    WHERE
        MAKE_DATE(pss.year, pss.month, pss.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    MD5(CONCAT(ss.id_answer, year, month, day)) AS id_answer,
    ss.id_survey,
    ss.id_contract,
    ss.id_ticket,
    ss.id_origin,
    ss.id_respondent,
    ss.respondent_email,
    ss.respondent_type,
    ss.survey_name,
    ss.service_type,
    ss.service_context,
    ss.source_name,
    ss.improvement_tags,
    ss.respondent_comments,
    ss.satisfaction_score,
    ss.score_description,
    ss.secondary_satisfaction_score,
    ss.secondary_score_description,
    ss.ts_submitted,
    ss.year,
    ss.month,
    ss.day
FROM
    survicate_surveys AS ss
WHERE
    MAKE_DATE(ss.year, ss.month, ss.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')