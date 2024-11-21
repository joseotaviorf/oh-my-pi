SELECT
    ID                  AS id_ratings_bradesco,
    IDUsuarioINI        AS id_user_started,
    IDUsuarioFIM        AS id_user_ended,
    Rating              AS rating,
    PercAprMaxRes       AS apr_max_res_percentage,
    PerAprAutoRes       AS apr_auto_res_percentage,
    PercAprMaxCom       AS apr_max_com_percentage,
    PerAprAutoCom       AS apr_auto_com_percentage,
    PerCpmrRendaRes     AS cpmr_income_res_percentage,
    PerCpmrRendaCom     AS cpmr_income_com_percentage,
    DtIniVigencia       AS ts_started,
    DtFimVigencia       AS ts_ended
FROM
    datalake_atta_test_raw.consulta_score_bradesco_ratings
