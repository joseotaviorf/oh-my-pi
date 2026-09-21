SELECT
    NULLIF(
        NULLIF(TRIM(review.matricula), ''),
        '-'
    ) AS assignment_number,
    NULLIF(NULLIF(TRIM(review.nome), ''), '-') AS name,
    NULLIF(NULLIF(TRIM(review.email), ''), '-') AS work_email,
    NULLIF(NULLIF(TRIM(review.lider), ''), '-') AS manager_name,
    NULLIF(NULLIF(TRIM(review.avaliador), ''), '-') AS evaluator_name,
    NULLIF(NULLIF(TRIM(review.tr_potencial), ''), '-') AS potential,
    NULLIF(NULLIF(TRIM(review.tr_prontidao), ''), '-') AS readiness,
    NULLIF(NULLIF(TRIM(review.tr_criticidade), ''), '-') AS criticality,
    NULLIF(NULLIF(TRIM(review.tr_risco_de_perda), ''), '-') AS risk_of_loss,
    NULLIF(
        NULLIF(TRIM(review.data_de_atualizacao), ''),
        '-'
    ) AS review_month,
    review.ts_load
FROM
    datalake_gsheets_people_raw.talent_review_h2_26 AS review
