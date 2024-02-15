SELECT
    email,
    nome AS name,
    modulo_1_2 AS module_1_2,
    modulo_3 AS module_3,
    media,
    certificado_enviado_em AS ts_certified,
    link_certificado AS certification_link,
    ts_load
FROM
    datalake_gsheets_raw.data_analytics_training_certificado_curso
