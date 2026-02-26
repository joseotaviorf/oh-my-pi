SELECT
    actfil.id_contract AS sk_contract,
    b.id_anonymized AS id_case,
    b.office,
    b.last_stage,
    actfil.action,
    a.code_description AS action_description,
    actfil.result,
    r.code_description AS result_description,
    actfil.complement,
    c.code_description AS complement_description
FROM datalake_cyber_clean.logs actfil
LEFT JOIN datalake_cyber_clean.logs_code_description a
    ON actfil.action = a.code
    AND a.code_type = 'Ação'
LEFT JOIN datalake_cyber_clean.logs_code_description r
    ON actfil.result = r.code
    AND r.code_type = 'Resultado'
LEFT JOIN datalake_cyber_clean.logs_code_description c
    ON actfil.complement = c.code
    AND c.code_type = 'Carta'
LEFT JOIN datalake_cyber_legal_homolog.evictions_base b
    ON actfil.id_contract = b.contract
