SELECT
    sa.id_answer AS sk_answer,
    sa.id_survey AS sk_survey,
    COALESCE(sa.id_contract, -1) AS sk_contract,
    COALESCE(sa.id_ticket, -1) AS sk_ticket,
    COALESCE(sa.id_origin, -1) AS sk_origin,
    COALESCE(sa.id_respondent, -1) AS sk_user,
    sa.satisfaction_score,
    sa.secondary_satisfaction_score,
    sa.ts_submitted,
    NOW() AS ts_load,
    sa.year,
    sa.month,
    sa.day
FROM
    datalake_satisfaction_rating.satisfaction_answers AS sa
WHERE
    MAKE_DATE(sa.year, sa.month, sa.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
