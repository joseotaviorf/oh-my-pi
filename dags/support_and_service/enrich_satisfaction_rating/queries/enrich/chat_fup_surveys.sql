WITH chat_fup_surveys AS (
    SELECT
        MD5(CONCAT(r.id_rating, r.year, r.month, r.day)) AS id_answer,
        NULL AS id_ticket,
        r.id_user AS id_respondent,
        NULL AS respondent_email,
        'customer support' AS service_type,
        r.channel AS service_context,
        'chat_fup_rating' AS source_name,
        r.meta AS improvement_tags,
        r.comment AS respondent_comments,
        r.grade AS satisfaction_score,
        "satisfaction evaluation" AS score_description,
        NULL AS secondary_satisfaction_score,
        NULL AS secondary_score_description,
        TO_JSON(NAMED_STRUCT('id_rating', r.id_rating, 'id_origin', r.id_origin, 'evaluated_tool', r.evaluated_tool, 'csat_version', r.csat_version)) AS custom_attributes,
        r.ts_created AS ts_submitted,
        r.year,
        r.month,
        r.day
    FROM
        datalake_chat_fup_clean.rating AS r
    WHERE
        MAKE_DATE(r.year, r.month, r.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    SELECT DISTINCT
        sa.id AS id_answer,
        cc.id_ticket,
        NULL AS id_respondent,
        cc.customer_email AS respondent_email,
        "customer support" AS service_type,
        'chat' AS service_context,
        'chat_fup' AS source_name,
        NULL AS improvement_tags,
        sa.comment AS respondent_comments,
        sa.rating AS satisfaction_score,
        "satisfaction evaluation" AS score_description,
        CASE
          WHEN sa.is_solved IS TRUE THEN 5
          WHEN sa.is_solved IS FALSE THEN 1
        END AS secondary_satisfaction_score,
        "resolution survey" AS secondary_score_description,
        TO_JSON(NAMED_STRUCT('id_survey', sa.id_survey, 'id_chat', ss.id_chat, "attendant_email", cc.attendant_email)) AS custom_attributes,
        sa.ts_created AS ts_submitted,
        YEAR(sa.ts_updated) AS year,
        MONTH(sa.ts_updated) AS month,
        DAY(sa.ts_updated) AS day
    FROM
        datalake_chat_fup_clean.surveys_answer sa
    JOIN
        datalake_chat_fup_clean.surveys_survey ss
            ON ss.id = sa.id_survey
    JOIN
        datalake_chat_fup_clean.chats_chat cc
            ON cc.id = ss.id_chat
    WHERE
        COALESCE(CAST(sa.is_solved AS string), CAST(sa.rating AS string)) IS NOT NULL
        AND DATE(sa.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT DISTINCT
    cfs.id_answer,
    MD5(cfs.source_name) AS id_survey,
    CAST(tfm.id_contract AS BIGINT) AS id_contract,
    cfs.id_ticket,
    cfs.id_respondent AS id_respondent,
    cfs.respondent_email AS respondent_email,
    cfs.service_type,
    cfs.service_context,
    cfs.source_name,
    cfs.improvement_tags,
    cfs.respondent_comments,
    cfs.satisfaction_score,
    cfs.score_description,
    cfs.secondary_satisfaction_score,
    cfs.secondary_score_description,
    cfs.custom_attributes,
    cfs.ts_submitted,
    cfs.year,
    cfs.month,
    cfs.day
FROM
    chat_fup_surveys AS cfs
LEFT JOIN
    datalake_zendesk.tickets_current AS tfm
        ON tfm.id_ticket = cfs.id_ticket
