WITH union_surveys_answers AS (
    SELECT
        ssg.id_answer,
        ssg.id_survey,
        ssg.id_contract,
        NULL AS id_ticket,
        NULL AS id_origin,
        NULL AS id_respondent,
        ssg.respondent_email,
        ssg.respondent_type,
        ssg.service_type,
        ssg.service_context,
        ssg.source_name,
        ssg.survey_name,
        ssg.improvement_tags,
        ssg.respondent_comments,
        ssg.satisfaction_score,
        ssg.score_description,
        ssg.secondary_satisfaction_score,
        ssg.secondary_score_description,
        ssg.custom_attributes,
        ssg.ts_submitted,
        ssg.year,
        ssg.month,
        ssg.day
    FROM
        datalake_satisfaction_rating.gsheets_surveys AS ssg
    WHERE
        MAKE_DATE(ssg.year, ssg.month, ssg.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

    UNION ALL

    SELECT
        ssz.id_answer,
        MD5(ssz.source_name) AS id_survey,
        ssz.id_contract,
        ssz.id_ticket,
        NULL AS id_origin,
        ssz.id_respondent,
        ssz.respondent_email,
        ssz.respondent_type,
        ssz.service_type,
        ssz.service_context,
        ssz.source_name,
        NULL AS survey_name,
        ssz.improvement_tags,
        NULL AS respondent_comments,
        ssz.satisfaction_score,
        ssz.score_description,
        NULL AS secondary_satisfaction_score,
        NULL AS secondary_score_description,
        NULL AS custom_attributes,
        ssz.ts_submitted,
        ssz.year,
        ssz.month,
        ssz.day
    FROM
        datalake_satisfaction_rating.zendesk_surveys AS ssz
    WHERE
        MAKE_DATE(ssz.year, ssz.month, ssz.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

    UNION ALL

    SELECT
        ssb.id_answer,
        MD5(ssb.source_name) AS id_survey,
        ssb.id_contract,
        ssb.id_ticket,
        NULL AS id_origin,
        NULL AS id_respondent,
        NULL AS respondent_email,
        NULL AS respondent_type,
        ssb.service_type,
        ssb.service_context,
        ssb.source_name,
        NULL AS survey_name,
        NULL AS improvement_tags,
        NULL AS respondent_comments,
        ssb.satisfaction_score,
        ssb.score_description,
        NULL AS secondary_satisfaction_score,
        NULL AS secondary_score_description,
        NULL AS custom_attributes,
        ssb.ts_submitted,
        ssb.year,
        ssb.month,
        ssb.day
    FROM
        datalake_satisfaction_rating.bigfone_surveys AS ssb
    WHERE
        MAKE_DATE(ssb.year, ssb.month, ssb.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

    UNION ALL

    SELECT
        sscf.id_answer,
        COALESCE(sscf.id_survey, MD5(sscf.source_name)) AS id_survey,
        sscf.id_contract,
        sscf.id_ticket,
        NULL AS id_origin,
        sscf.id_respondent,
        sscf.respondent_email,
        NULL AS respondent_type,
        sscf.service_type,
        sscf.service_context,
        sscf.source_name,
        NULL AS survey_name,
        sscf.improvement_tags,
        sscf.respondent_comments,
        sscf.satisfaction_score,
        sscf.score_description,
        sscf.secondary_satisfaction_score,
        sscf.secondary_score_description,
        sscf.custom_attributes,
        sscf.ts_submitted,
        sscf.year,
        sscf.month,
        sscf.day
    FROM
        datalake_satisfaction_rating.chat_fup_surveys AS sscf
    WHERE
        MAKE_DATE(sscf.year, sscf.month, sscf.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

    UNION ALL

    SELECT
        sss.id_answer,
        sss.id_survey,
        sss.id_contract,
        sss.id_ticket,
        sss.id_origin,
        sss.id_respondent,
        sss.respondent_email,
        sss.respondent_type,
        sss.service_type,
        sss.service_context,
        sss.source_name,
        sss.survey_name,
        sss.improvement_tags,
        sss.respondent_comments,
        sss.satisfaction_score,
        sss.score_description,
        sss.secondary_satisfaction_score,
        sss.secondary_score_description,
        NULL AS custom_attributes,
        sss.ts_submitted,
        sss.year,
        sss.month,
        sss.day
    FROM
        datalake_satisfaction_rating.survicate_surveys AS sss
    WHERE
        MAKE_DATE(sss.year, sss.month, sss.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
users AS (
    SELECT
        u.id AS id_user,
        LOWER(u.email) AS email
    FROM
        datalake_ebdb_user.user AS u
    WHERE
        DATE(u.ts_updated) <= DATE('{load_end_date}')
    QUALIFY
        u.ts_updated = FIRST(u.ts_updated) OVER(PARTITION BY LOWER(u.email) ORDER BY u.ts_updated DESC)
)
SELECT DISTINCT
    usa.id_answer,
    usa.id_survey,
    usa.id_contract,
    usa.id_ticket,
    usa.id_origin,
    COALESCE(usa.id_respondent, ue.id_user) AS id_respondent,
    COALESCE(usa.respondent_email, ue.email) AS respondent_email,
    usa.respondent_type,
    usa.service_type,
    usa.service_context,
    usa.source_name,
    usa.survey_name,
    usa.improvement_tags,
    usa.respondent_comments,
    usa.satisfaction_score,
    usa.score_description,
    usa.secondary_satisfaction_score,
    usa.secondary_score_description,
    usa.custom_attributes,
    usa.ts_submitted,
    usa.year,
    usa.month,
    usa.day
FROM
    union_surveys_answers AS usa
LEFT JOIN
    users AS ue
        ON ue.email = LOWER(usa.respondent_email)
        OR ue.id_user = usa.id_respondent