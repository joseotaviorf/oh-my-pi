SELECT
    ID          AS id_pre_analysis_matrix,
    Itau        AS itau,
    Bradesco    AS bradesco,
    Santander   AS santander
FROM
    datalake_atta_test_raw.consulta_score_santander_matriz_decisao
