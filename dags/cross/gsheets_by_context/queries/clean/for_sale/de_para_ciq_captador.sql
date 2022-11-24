SELECT
    CAST(id_ciq_5a AS BIGINT) AS id_ciq_5a,
    CAST(id_captador_cm AS BIGINT) AS id_captador_cm,
    name,
    email,
    cpf
FROM
    datalake_gsheets_raw.de_para_ciq_captador