SELECT
    NULLIF(sk_broker, '') AS sk_broker,
    NULLIF(id_pipedrive, '') AS id_pipedrive,
    NULLIF(broker_name, '') AS broker_name,
    NULLIF(cnpj, '') AS cnpj,
    NULLIF(potential_segmentation, '') AS potential_segmentation,
    NULLIF(credit_segmentation, '') AS credit_segmentation,
    NULLIF(status_imob, '') AS status_imob,
    NULLIF(status, '') AS status,
    NULLIF(executivo, '') AS executivo
FROM
    datalake_gsheets_raw.quintocred_real_estates
