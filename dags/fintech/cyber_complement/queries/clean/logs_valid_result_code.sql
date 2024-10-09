SELECT
    VCACTYPE AS action_type,
    VCACCODE AS id_action,
    VCRCTYPE AS result_type,
    VCRCCODE AS id_result,
    VCCMTPREFIX AS comment_pre_defined,
    VCACCTG AS group,
    CASE
        WHEN UPPER(VCMODULE) = 'L' THEN 'CyberLegal'
        WHEN UPPER(VCMODULE) = 'N' THEN 'Todos os demais'
        ELSE UPPER(VCMODULE)
    END AS module,
    NOW() AS ts_load
FROM datalake_cyber_raw.valcodes
