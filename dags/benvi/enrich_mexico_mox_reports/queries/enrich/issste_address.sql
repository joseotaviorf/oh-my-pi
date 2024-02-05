SELECT
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.curp") AS curp,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosDomicilio.calle") AS street,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosDomicilio.estado") AS state,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosDomicilio.colonia") AS neighborhood,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosDomicilio.codigoPostal") AS postal_code,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosDomicilio.numeroExterior") AS exterior_number,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosDomicilio.numeroInterior") AS interior_number,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosDomicilio.delegacionMunicipio") AS municipality,
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
