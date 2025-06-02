SELECT
    imovel_id AS id_house,
    informacoesVisita AS visit_information,
    NOW() AS ts_load
FROM
    datalake_ebdb_raw.Imovel_InformacoesVisita
