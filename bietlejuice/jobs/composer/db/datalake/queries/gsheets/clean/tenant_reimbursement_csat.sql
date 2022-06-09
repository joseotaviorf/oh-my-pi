SELECT
    NULLIF(token,'') AS id_csat_answer,
    INT(NULLIF(contract_id,'')) AS id_contract,
    INT(NULLIF(user_id,'')) AS id_user,
    NULLIF(comments,'') AS comments,
    NULLIF(improvement_tags,'') AS improvement_tags,
    NULLIF(score_text,'') AS score_text,
    INT(NULLIF(score,'')) AS score,
    TO_TIMESTAMP(NULLIF(submitted_at,''),'M/d/y H:m:s') AS ts_submitted
FROM
    datalake_gsheets_raw.csat_reembolso_iq