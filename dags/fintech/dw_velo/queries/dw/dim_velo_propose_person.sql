SELECT
    id_person AS sk_person,
    name,
    email,
    bureau_name,
    document,
    serasa_score,
    risk_score,
    risk_classification,
    score_personal_value,
    declared_income,
    requested_income,
    is_primary_person,
    dt_birth,
    NOW() AS ts_load
FROM
    datalake_velo.propose_person
