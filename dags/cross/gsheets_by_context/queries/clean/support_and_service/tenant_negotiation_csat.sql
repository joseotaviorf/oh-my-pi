SELECT
    NULLIF(token,'') AS id_csat_answer,
    INT(NULLIF(contract_id,'')) AS id_contract,
    NULLIF(comments,'') AS comments,
    NULLIF(score_text,'') AS score_text,
    TO_TIMESTAMP(NULLIF(submitted_at,''),'M/d/y H:m:s') AS ts_submitted
FROM
    datalake_gsheets_raw.csat_negociacao_iq