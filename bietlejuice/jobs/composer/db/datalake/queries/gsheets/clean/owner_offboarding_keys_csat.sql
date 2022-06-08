SELECT
    NULLIF(tags,'') AS improvement_tags,
    NULLIF(comments,'') AS comments,
    INT(NULLIF(score,'')) AS score,
    TO_TIMESTAMP(NULLIF(ts_input,''),'M/d/y H:m:s') AS ts_input
FROM
    datalake_gsheets_raw.csat_chaves_off_pp