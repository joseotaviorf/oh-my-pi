WITH base AS (
  SELECT
    contract_analysis_job_id AS id_contract_analysis_job,
    sales_flow_id AS id_sales_flow,
    CAST(created_at AS DATE) AS analysis_date,
    GET_JSON_OBJECT(analysis_metadata, '$.request_source') AS request_source,
    analysis_started_at AS ts_analysis_started,
    analysis_ended_at AS ts_analysis_end,
    full_analysis
  FROM datalake_legalops_raw.contract_analysis_request
  WHERE
    status = 'DONE'
    AND MAKE_DATE(year, month, day)
        BETWEEN DATE('{load_start_date}')
        AND DATE('{load_end_date}')
), parsed AS (
  SELECT
    id_contract_analysis_job,
    id_sales_flow,
    analysis_date,
    request_source,
    ts_analysis_started,
    ts_analysis_end,
    FROM_JSON(
      GET_JSON_OBJECT(full_analysis, '$.validation_results'),
      'array<struct<rule_id:string,status:string,assessments:array<struct<validation_id:string,confidence:string,subsection:string,assessment_type:string,assessment_status:string,assessment_target:string,assessment_consolidated_status:string>>>>'
    ) AS validation_results
  FROM base
), exploded_validations AS (
  SELECT
    id_contract_analysis_job,
    id_sales_flow,
    analysis_date,
    request_source,
    ts_analysis_started,
    ts_analysis_end,
    vr AS validation_result
  FROM parsed
  LATERAL VIEW
  EXPLODE(validation_results) t AS vr
)
SELECT
  id_contract_analysis_job,
  id_sales_flow,
  analysis_date,
  request_source,
  assessment.validation_id AS validation_id,
  assessment.assessment_target AS assessment_name,
  assessment.assessment_status AS assessment_status,
  assessment.assessment_consolidated_status AS assessment_consolidated_status,
  assessment.confidence AS assessment_confidence,
  ts_analysis_started,
  ts_analysis_end
FROM exploded_validations
LATERAL VIEW
EXPLODE(validation_result.assessments) t AS assessment
