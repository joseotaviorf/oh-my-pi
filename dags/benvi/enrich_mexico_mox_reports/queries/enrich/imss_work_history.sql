WITH json_extraction AS (
    SELECT
        GET_JSON_OBJECT(attributes, "$.IMSS.curp") AS curp,
        EXPLODE(FROM_JSON(GET_JSON_OBJECT(attributes, "$.IMSS.data.historialLaboral"), 'ARRAY<STRING>')) AS work_history,
        rev.ts_created
    FROM
        datalake_arquivo_confidencial_clean.presumed_income_report_aud AS aud
    JOIN
        datalake_arquivo_confidencial_clean.rev_info AS rev
            ON rev.rev = aud.rev
    WHERE
        source = 'MOX'
        AND attributes LIKE '%IMSS%'
        AND YEAR(rev.ts_created) = {year}
        AND MONTH(rev.ts_created) = {month}
        AND DAY(rev.ts_created) = {day}
),
data_formatting AS (
    SELECT
        curp,
        GET_JSON_OBJECT(work_history, "$.registroPatronal") AS employer_registry,
        GET_JSON_OBJECT(work_history, "$.nombrePatron") AS company_name,
        GET_JSON_OBJECT(work_history, "$.entidadFederativa") AS federative_entity,
        FLOAT(REPLACE(GET_JSON_OBJECT(work_history, "$.salarioBaseCotizacion"), '$', '')) AS base_salary_contribution,
        FLOAT(REPLACE(GET_JSON_OBJECT(work_history, "$.salarioMensual"), '$', '')) AS monthly_salary,
        GET_JSON_OBJECT(work_history, "$.antiguedad") AS time_worked,
        TO_DATE(GET_JSON_OBJECT(work_history, "$.fechaAlta"), 'dd/MM/yyyy') AS dt_work_started,
        IF(GET_JSON_OBJECT(work_history, "$.fechaBaja") = 'Vigente', NULL, TO_DATE(GET_JSON_OBJECT(work_history, "$.fechaBaja"), 'dd/MM/yyyy')) AS dt_work_ended,
        ts_created AS ts_report
    FROM
        json_extraction
)
SELECT
    curp,
    employer_registry,
    company_name,
    federative_entity,
    base_salary_contribution,
    monthly_salary,
    IF(dt_work_ended IS NULL AND time_worked = 'Vigente', TRUE, FALSE) AS is_current_work,
    time_worked,
    dt_work_started,
    dt_work_ended,
    ts_report,
    YEAR(ts_report) AS year,
    MONTH(ts_report) AS month,
    DAY(ts_report) AS day
FROM
    data_formatting
