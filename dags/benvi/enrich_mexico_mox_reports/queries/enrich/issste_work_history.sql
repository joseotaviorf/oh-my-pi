WITH json_extraction AS (
    SELECT
        GET_JSON_OBJECT(attributes, "$.ISSSTE.datosPersonales.curp") AS curp,
        EXPLODE(FROM_JSON(GET_JSON_OBJECT(attributes, "$.ISSSTE.historialCotizacion"), 'ARRAY<STRING>')) AS work_history,
        rev.ts_created,
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
),
employment_details_extraction AS (
    SELECT
        curp,
        GET_JSON_OBJECT(work_history, "$.ramo") AS department,
        GET_JSON_OBJECT(work_history, "$.pagaduria") AS payment_institution,
        EXPLODE(FROM_JSON(GET_JSON_OBJECT(work_history, "$.informacionDeEmpleo"), 'ARRAY<STRING>')) AS employment_details,
        ts_created AS ts_report,
        year,
        month,
        day
    FROM
        json_extraction
)
SELECT
    curp,
    department,
    payment_institution,
    GET_JSON_OBJECT(employment_details, "$.tipo") AS contribution_type,
    CASE
        WHEN GET_JSON_OBJECT(employment_details, "$.cotiza") = "SÍ" THEN TRUE
        WHEN GET_JSON_OBJECT(employment_details, "$.cotiza") = "NO" THEN FALSE
    END AS has_contributed,
    FLOAT(TRANSLATE(GET_JSON_OBJECT(employment_details, "$.sueldoBasico"), "$,", "")) AS basic_salary,
    TO_DATE(GET_JSON_OBJECT(employment_details, "$.fechaDeInicio"), 'dd/MM/yyyy') AS dt_work_started,
    TO_DATE(GET_JSON_OBJECT(employment_details, "$.fechaDeTermino"), 'dd/MM/yyyy') AS dt_work_ended,
    ts_report,
    year,
    month,
    day
FROM
    employment_details_extraction
