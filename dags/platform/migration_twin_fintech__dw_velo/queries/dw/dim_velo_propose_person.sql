SELECT DISTINCT
    id_person AS sk_person,
    name,
    email,
    phone,
    bureau_name,
    document,
    serasa_score,
    risk_score,
    risk_classification,
    score_personal_value,
    declared_income,
    requested_income,
    dt_birth,
    is_legacy,
    NOW() AS ts_load
FROM
    datalake_velo.propose_person

UNION ALL

SELECT DISTINCT
    id_person AS sk_person,
    name,
    email,
    phone,
    bureau_name,
    document,
    serasa_score,
    risk_score,
    risk_classification,
    score_personal_value,
    declared_income,
    requested_income,
    dt_birth,
    is_legacy,
    NOW() AS ts_load
FROM
    datalake_velo.propose_person_legacy
