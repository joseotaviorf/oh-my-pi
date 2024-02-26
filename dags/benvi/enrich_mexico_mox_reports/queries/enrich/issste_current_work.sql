WITH json_extraction AS (
    SELECT
        GET_JSON_OBJECT(attributes, "$.ISSSTE.datosPersonales.curp") AS curp,
        EXPLODE(FROM_JSON(GET_JSON_OBJECT(attributes, "$.ISSSTE.datosLaborales.workerPosition"), 'ARRAY<STRING>')) AS worker_position,
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
worker_position_extraction AS (
    SELECT
        curp,
        GET_JSON_OBJECT(worker_position, "$.ramo") AS department,
        GET_JSON_OBJECT(worker_position, "$.pagaduria") AS payment_institution,
        EXPLODE(FROM_JSON(GET_JSON_OBJECT(worker_position, "$.informacionDeEmpleo"), 'ARRAY<STRING>')) AS employment_details,
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
    GET_JSON_OBJECT(employment_details, "$.modalidad") AS employment_modality,
    GET_JSON_OBJECT(employment_details, "$.nombramiento") AS position_title,
    FLOAT(TRANSLATE(GET_JSON_OBJECT(employment_details, "$.sueldoBasico"), "$,", "")) AS basic_salary,
    FLOAT(TRANSLATE(GET_JSON_OBJECT(employment_details, "$.remuneracionTotal"), "$,", "")) AS total_remuneration,
    TO_DATE(GET_JSON_OBJECT(employment_details, "$.fechaDeAlta"), 'dd/MM/yyyy') AS dt_work_started,
    ts_report,
    year,
    month,
    day
FROM
    worker_position_extraction
