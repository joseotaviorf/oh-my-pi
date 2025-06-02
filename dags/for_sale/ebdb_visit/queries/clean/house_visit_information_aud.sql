SELECT
    imovel_id AS id_house,
    informacoesVisita AS visit_information,
    rev,
    revtype AS rev_type,
    NOW() AS ts_load
FROM
    datalake_ebdb_raw.Imovel_InformacoesVisita_AUD
