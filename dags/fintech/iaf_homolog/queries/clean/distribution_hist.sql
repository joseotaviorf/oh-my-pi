SELECT
    id,
    processo AS process,
    data_distri2 AS dt_distribution_2,
    usuario_distri AS user_distribution,
    cobrador AS charger,
    data_distri_dias AS dt_distribution_days,
    data_saida AS dt_exit,
    last_update AS ts_updated
FROM
    datalake_iaf_raw.vi_319_tb_distribuicao_hist
