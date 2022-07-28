SELECT
    CAST(id_house AS BIGINT) AS id_house,
    id_user_hotjar,
    find_the_time,
    reason,
    comment,
    CAST(ts_answer_submitted AS TIMESTAMP) AS ts_answer_submitted
FROM
    datalake_gsheets_raw.hotjar_demanda_reprimida_fotos
