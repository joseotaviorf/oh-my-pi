SELECT
    CAST(id_imovel_5a AS BIGINT) AS id_house_quintoandar,
    CAST(id_ciq_5a AS BIGINT) AS id_ciq_quintoandar,
    name_participante AS name_participant,
    email,
    participante AS participant,
    CAST(n_participantes AS INT) AS n_participants,
    CAST(perc_captacao AS FLOAT) AS perc_captation
FROM
    datalake_gsheets_raw.split_ciq_bh