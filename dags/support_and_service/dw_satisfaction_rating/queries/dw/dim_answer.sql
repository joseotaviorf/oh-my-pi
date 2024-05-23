SELECT
    sa.id_answer AS sk_answer,
    sa.respondent_type,
    sa.improvement_tags,
    sa.respondent_comments,
    sa.score_description,
    sa.secondary_score_description,
    sa.custom_attributes,
    sa.ts_submitted,
    NOW() AS ts_load,
    sa.year,
    sa.month,
    sa.day
FROM
    datalake_satisfaction_rating.satisfaction_answers AS sa
WHERE
    MAKE_DATE(sa.year, sa.month, sa.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
