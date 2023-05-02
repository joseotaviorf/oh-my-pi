SELECT
    INT(NULLIF(contractid,'')) AS id_contract,
    NULLIF(token,'') AS id_csat_answer,
    email,
    NULLIF(comment,'') AS comment,
    NULLIF(tags,'') AS tags,
    INT(NULLIF(house_satisfaction_history,'')) AS house_satisfaction_history,
    INT(NULLIF(house_satisfaction,'')) AS house_satisfaction,,
    INT(NULLIF(inspection_satisfaction_history,'')) AS inspection_satisfaction_history,
    INT(NULLIF(inspection_satisfaction,'')) AS inspection_satisfaction,
    TO_TIMESTAMP(NULLIF(submitted_at,''),'M/d/y H:m:s') AS ts_submitted
FROM
    datalake_gsheets_raw.csat_vistoria_iq_saida
