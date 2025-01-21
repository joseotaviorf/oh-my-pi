SELECT
    CAST(idtitulovx AS BIGINT) AS id_vx_security,
    cedentecnpjcpf AS assignor_cnpj,
    cedentenome AS assignor_name,
    sacadocnpjcpf AS withdraw_cnpj_cpf,
    sacadonome AS withdraw_name,
    tipo AS type,
    tipoativo AS asset_type,
    campochave AS key_field,
    NULLIF(cmc7, "") AS cmc7,
    numerotitulo AS security_number,
    CAST(valoraquisicao AS FLOAT) AS acquisition_value,
    CAST(valornominal AS FLOAT) AS nominal_value,
    CAST(numeroboleto AS BIGINT) AS invoice_number,
    TO_DATE(dataemissao, "d/M/y") AS dt_emission,
    TO_DATE(dataaquisicao, "d/M/y") AS dt_acquisition,
    TO_DATE(datavencimento, "d/M/y") AS dt_due
FROM
    datalake_gsheets_raw.fdic_acquisition_2023