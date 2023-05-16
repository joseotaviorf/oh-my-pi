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
    sa.year = {year}
    AND sa.month = {month}
    AND sa.day = {day}