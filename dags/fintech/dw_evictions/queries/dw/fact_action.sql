SELECT
    actfil.id_case AS sk_case,
    b.contract,
    CASE
        WHEN b.office IN ('PLC', 'LLC') THEN 'LLC'
        ELSE b.office
    END AS office,
    b.last_stage,
    actfil.action,
    a.code_description AS action_description,
    actfil.result,
    r.code_description AS result_description,
    actfil.complement,
    c.code_description AS complement_description,
    actfil.comment,
    actfil.ts_activity
FROM datalake_cyber_legal_clean.logs_juridical actfil
LEFT JOIN datalake_cyber_legal.evictions_base b
    ON actfil.id_case = b.id_process
    AND DATE(actfil.ts_activity) >= DATE(b.dt_registered)
LEFT JOIN datalake_cyber_clean.logs_code_description a
    ON actfil.action = a.code
    AND a.code_type = 'Ação'
    AND a.group = 'Para legal'
LEFT JOIN datalake_cyber_clean.logs_code_description r
    ON actfil.result = r.code
    AND r.code_type = 'Resultado'
    AND r.group = 'Para legal'
LEFT JOIN datalake_cyber_clean.logs_code_description c
    ON actfil.complement = c.code
    AND c.code_type = 'Carta'
    AND c.group = 'Para legal'
WHERE a.code IS NOT NULL
