WITH gsheets_surveys AS (
    SELECT
        id_contract,
        NULL AS id_respondent,
        email AS respondent_email,
        'OWNER' AS respondent_type,
        'inspection' AS service_type,
        'offboarding' AS service_context,
        'gsheets' AS source_name,
        'owner_exit_inspection_csat' AS survey_name,
        improvement_tags,
        comments AS respondent_comments,
        general_satisfaction_evaluation AS satisfaction_score,
        'satisfaction evaluation' AS score_description,
        general_satisfaction_house AS secondary_satisfaction_score,
        'house satisfaction' AS secondary_score_description,
        NULL AS custom_attributes,
        ts_submitted,
        YEAR(ts_submitted) AS year,
        MONTH(ts_submitted) AS month,
        DAY(ts_submitted) AS day
    FROM
        datalake_gsheets_clean.owner_exit_inspection_csat
    WHERE
        DATE(ts_submitted) = DATE('{year}-{month}-{day}')
    UNION ALL
    SELECT
        id_contract,
        NULL AS id_respondent,
        email AS respondent_email,
        'TENANT' AS respondent_type,
        'inspection' AS service_type,
        'offboarding' AS service_context,
        'gsheets' AS source_name,
        'tenant_exit_inspection_csat' AS survey_name,
        tags AS improvement_tags,
        comment AS respondent_comments,
        COALESCE(inspection_satisfaction, inspection_satisfaction_history_first, inspection_satisfaction_history_second) AS satisfaction_score,
        'satisfaction evaluation' AS score_description,
        NULL AS secondary_satisfaction_score,
        NULL AS secondary_score_description,
        TO_JSON(NAMED_STRUCT('id_csat', id_csat_answer)) AS custom_attributes,
        ts_submitted,
        YEAR(ts_submitted) AS year,
        MONTH(ts_submitted) AS month,
        DAY(ts_submitted) AS day
    FROM
        datalake_gsheets_clean.tenant_exit_inspection_csat
    WHERE
        DATE(ts_submitted) = DATE('{year}-{month}-{day}')
    UNION ALL
    SELECT
        id_contract,
        NULL AS id_respondent,
        email AS respondent_email,
        'TENANT' AS respondent_type,
        'inspection' AS service_type,
        'onboarding' AS service_context,
        'gsheets' AS source_name,
        'tenant_entrance_inspection_csat' AS survey_name,
        improvement_tags,
        comments AS respondent_comments,
        general_satisfaction_evaluation AS satisfaction_score,
        'satisfaction evaluation' AS score_description,
        house_satisfation AS secondary_satisfaction_score,
        'house satisfaction' AS secondary_score_description,
        TO_JSON(NAMED_STRUCT('id_csat', id_csat)) AS custom_attributes,
        ts_submitted,
        YEAR(ts_submitted) AS year,
        MONTH(ts_submitted) AS month,
        DAY(ts_submitted) AS day
    FROM
        datalake_gsheets_clean.tenant_entrance_inspection_csat
    WHERE
        DATE(ts_submitted) = DATE('{year}-{month}-{day}')
    UNION ALL
    SELECT
        id_contract,
        NULL AS id_respondent,
        email AS respondent_email,
        'OWNER' AS respondent_type,
        'inspection' AS service_type,
        'onboarding' AS service_context,
        'gsheets' AS source_name,
        'owner_entrance_inspection_csat' AS survey_name,
        improvement_tags,
        comments AS respondent_comments,
        general_satisfaction_evaluation AS satisfaction_score,
        'satisfaction evaluation' AS score_description,
        NULL AS secondary_satisfaction_score,
        NULL AS secondary_score_description,
        NULL AS custom_attributes,
        ts_submitted,
        YEAR(ts_submitted) AS year,
        MONTH(ts_submitted) AS month,
        DAY(ts_submitted) AS day
    FROM
        datalake_gsheets_clean.owner_entrance_inspection_csat
    WHERE
        DATE(ts_submitted) = DATE('{year}-{month}-{day}')
    UNION ALL
    SELECT
        id_contract,
        id_user AS id_respondent,
        NULL AS respondent_email,
        'TENANT' AS respondent_type,
        'keys' AS service_type,
        'onboarding' AS service_context,
        'gsheets' AS source_name,
        'tenant_reimbursement_csat' AS survey_name,
        improvement_tags,
        comments AS respondent_comments,
        score AS satisfaction_score,
        score_text AS score_description,
        NULL AS secondary_satisfaction_score,
        NULL AS secondary_score_description,
        TO_JSON(NAMED_STRUCT('id_csat_answer', id_csat_answer)) AS custom_attributes,
        ts_submitted,
        YEAR(ts_submitted) AS year,
        MONTH(ts_submitted) AS month,
        DAY(ts_submitted) AS day
    FROM
        datalake_gsheets_clean.tenant_reimbursement_csat
    WHERE
        DATE(ts_submitted) = DATE('{year}-{month}-{day}')
    UNION ALL
    SELECT
        NULL AS id_contract,
        NULL AS id_respondent,
        NULL AS respondent_email,
        NULL AS respondent_type,
        'reimbursement' AS service_type,
        NULL AS service_context,
        'gsheets' AS source_name,
        'csat_reimbursement_true' AS survey_name,
        improvement_suggestions AS improvement_tags,
        satisfation_level_reason AS respondent_comments,
        satisfation_level AS satisfaction_score,
        satisfation_level_description AS score_description,
        NULL AS secondary_satisfaction_score,
        NULL AS secondary_score_description,
        TO_JSON(NAMED_STRUCT('token', token, 'cid', cid, 'uid', uid)) AS custom_attributes,
        ts_submitted,
        YEAR(ts_submitted) AS year,
        MONTH(ts_submitted) AS month,
        DAY(ts_submitted) AS day
    FROM
        datalake_gsheets_clean.csat_reimbursement_true
    WHERE
        DATE(ts_submitted) = DATE('{year}-{month}-{day}')
)
SELECT DISTINCT
    MD5(CONCAT(COALESCE(gs.id_contract, ''), gs.source_name, gs.survey_name, COALESCE(gs.ts_submitted, ''))) AS id_answer,
    MD5(CONCAT(gs.source_name, gs.survey_name)) AS id_survey,
    gs.id_contract,
    gs.id_respondent,
    gs.respondent_email,
    gs.respondent_type,
    gs.service_type,
    gs.service_context,
    gs.source_name,
    gs.survey_name,
    gs.improvement_tags,
    gs.respondent_comments,
    gs.satisfaction_score,
    gs.score_description,
    gs.secondary_satisfaction_score,
    gs.secondary_score_description,
    gs.custom_attributes,
    gs.ts_submitted,
    gs.year,
    gs.month,
    gs.day
FROM
    gsheets_surveys AS gs