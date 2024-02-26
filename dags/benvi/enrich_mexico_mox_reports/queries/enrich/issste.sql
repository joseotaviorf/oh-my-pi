SELECT
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.curp") AS curp,
    BIGINT(GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.nss")) AS nss,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.rfc") AS rfc,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.nombre") AS name,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.primerApellido") AS first_surname,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.segundoApellido") AS second_surname,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.sexo") AS gender,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.estadoCivil") AS marital_status,
    CASE
        WHEN GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.tipoDerechohabiente") = 'PENSIONISTA' THEN TRUE
        WHEN GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.tipoDerechohabiente") = 'TRABAJADOR' THEN FALSE
    END AS is_pensioner,
    CASE
        WHEN GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.situacionAfiliatoria") = 'ACTIVO' THEN TRUE
        WHEN GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.situacionAfiliatoria") = 'INACTIVO' THEN FALSE
    END AS is_active,
    aud.presumed_income,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.regimenPensionario.regimenPensionario") AS type_pension,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.regimenPensionario.antiguedadParaPensiones") AS time_pension,
    TO_DATE(GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.fechaDeNacimiento"), 'dd/MM/yyyy') AS dt_birth,
    TO_DATE(GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.fechaAltaPlazaActual"), 'dd/MM/yyyy') AS dt_work_started,
    TO_DATE(GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.fechaDeBaja"), 'dd/MM/yyyy') AS dt_work_ended,
    TO_DATE(GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.fechaAltaGobiernoFederal"), 'dd/MM/yyyy') AS dt_government_work_started,
    rev.ts_created AS ts_report,
    rev.year,
    rev.month,
    rev.day
FROM
    datalake_arquivo_confidencial_clean.presumed_income_report_aud AS aud
JOIN
    datalake_arquivo_confidencial_clean.rev_info AS rev
        ON rev.rev = aud.rev
WHERE
    rev.year = {year}
    AND rev.month = {month}
    AND rev.day = {day}
    AND source = 'MOX'
    AND attributes LIKE '%ISSSTE%'
