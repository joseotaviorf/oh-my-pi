SELECT
    id,
    iddevolucao AS id_return,
    idempresa AS id_company,
    idtitulo AS id_title,
    last_update AS ts_updated
FROM
    datalake_iaf_raw.vi_319_tb_devolucao_tit
