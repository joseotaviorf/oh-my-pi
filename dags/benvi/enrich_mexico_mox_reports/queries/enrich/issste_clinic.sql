SELECT
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosPersonales.curp") AS curp,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosClinica.clinica") AS name,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosClinica.colonia") AS neighborhood,
    SPLIT(TRANSLATE(GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosClinica.telefono"), "- ", ""), "[,;]") AS phone,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosClinica.domicilio") AS address,
    GET_JSON_OBJECT(aud.attributes, "$.ISSSTE.datosClinica.delegacionISSSTE") AS delegation,
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
