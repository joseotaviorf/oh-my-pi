WITH base AS (
  SELECT
    sales_flow_id AS id_sales_flow,
    DATE(created_at) AS analysis_date,
    full_analysis
  FROM datalake_legalops_raw.contract_analysis_request
  WHERE status = 'DONE'
),

parsed AS (
  SELECT
    id_sales_flow,
    analysis_date,
    from_json(
      get_json_object(full_analysis, '$.validation_results'),
      'array<struct<rule_id:string,status:string,assessments:array<struct<validation_id:string,confidence:string,subsection:string,assessment_type:string,assessment_status:string,assessment_target:string,assessment_consolidated_status:string>>>>'
    ) AS validation_results
  FROM base
),

exploded_validations AS (
  SELECT
    id_sales_flow,
    analysis_date,
    vr AS validation_result
  FROM parsed
  LATERAL VIEW explode(validation_results) t AS vr
)

SELECT
  id_sales_flow,
  analysis_date,
  assessment.validation_id                   AS validation_id,
  assessment.assessment_target               AS assessment_name,
  assessment.assessment_status               AS assessment_status,
  assessment.assessment_consolidated_status  AS assessment_consolidated_status,
  assessment.confidence                      AS assessment_confidence
FROM exploded_validations
LATERAL VIEW explode(validation_result.assessments) t AS assessment