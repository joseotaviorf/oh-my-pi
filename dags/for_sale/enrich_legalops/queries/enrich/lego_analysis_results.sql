WITH base AS (
  SELECT
    id_sales_flow,
    DATE(ts_created) as analysis_date,
    contract_analysis_result
  FROM datalake_legalops_clean.contract_analysis_request
  where status = 'DONE'
),

parsed AS (
  SELECT
    id_sales_flow,
    analysis_date,
    from_json(get_json_object(contract_analysis_result, '$.validations.house.assessments'),
      'map<string, struct<validation_id:string, assessment_confidence:string, assessment_consolidated_status:string, assessment_status:string>>'
    ) AS house_assessments,

    from_json(get_json_object(contract_analysis_result, '$.validations.buyers.section_assessments'),
      'map<string, struct<validation_id:string, assessment_confidence:string, assessment_consolidated_status:string, assessment_status:string>>'
    ) AS buyers_section_assessments,

    from_json(get_json_object(contract_analysis_result, '$.validations.sellers.section_assessments'),
      'map<string, struct<validation_id:string, assessment_confidence:string, assessment_consolidated_status:string, assessment_status:string>>'
    ) AS sellers_section_assessments,

    from_json(get_json_object(contract_analysis_result, '$.validations.buyers.parties'),
      'array<struct<party_id:string, party_name:string, assessments:map<string, struct<validation_id:string, assessment_confidence:string, assessment_consolidated_status:string, assessment_status:string>>>>'
    ) AS buyers_parties,

    from_json(get_json_object(contract_analysis_result, '$.validations.sellers.parties'),
      'array<struct<party_id:string, party_name:string, assessments:map<string, struct<validation_id:string, assessment_confidence:string, assessment_consolidated_status:string, assessment_status:string>>>>'
    ) AS sellers_parties

  FROM base
),

all_assessments AS (
  SELECT
    id_sales_flow,
    analysis_date,
    concat(

      coalesce(transform(map_entries(house_assessments), e -> map(
        'assessment_name',                e.key,
        'validation_id',                  e.value.validation_id,
        'assessment_confidence',          e.value.assessment_confidence,
        'assessment_consolidated_status', e.value.assessment_consolidated_status,
        'assessment_status',              e.value.assessment_status
      )), array()),

      coalesce(transform(map_entries(buyers_section_assessments), e -> map(
        'assessment_name',                e.key,
        'validation_id',                  e.value.validation_id,
        'assessment_confidence',          e.value.assessment_confidence,
        'assessment_consolidated_status', e.value.assessment_consolidated_status,
        'assessment_status',              e.value.assessment_status
      )), array()),

      coalesce(transform(map_entries(sellers_section_assessments), e -> map(
        'assessment_name',                e.key,
        'validation_id',                  e.value.validation_id,
        'assessment_confidence',          e.value.assessment_confidence,
        'assessment_consolidated_status', e.value.assessment_consolidated_status,
        'assessment_status',              e.value.assessment_status
      )), array()),

      coalesce(flatten(transform(
        coalesce(buyers_parties, array()),
        party -> coalesce(transform(map_entries(party.assessments), e -> map(
          'assessment_name',                e.key,
          'validation_id',                  e.value.validation_id,
          'assessment_confidence',          e.value.assessment_confidence,
          'assessment_consolidated_status', e.value.assessment_consolidated_status,
          'assessment_status',              e.value.assessment_status
        )), array())
      )), array()),

      coalesce(flatten(transform(
        coalesce(sellers_parties, array()),
        party -> coalesce(transform(map_entries(party.assessments), e -> map(
          'assessment_name',                e.key,
          'validation_id',                  e.value.validation_id,
          'assessment_confidence',          e.value.assessment_confidence,
          'assessment_consolidated_status', e.value.assessment_consolidated_status,
          'assessment_status',              e.value.assessment_status
        )), array())
      )), array())

    ) AS assessments

  FROM parsed
)

SELECT
  id_sales_flow,
  analysis_date,
  assessment['validation_id']                  AS validation_id,
  assessment['assessment_name']                AS assessment_name,
  assessment['assessment_status']              AS assessment_status,
  assessment['assessment_consolidated_status'] AS assessment_consolidated_status,
  assessment['assessment_confidence']          AS assessment_confidence
FROM all_assessments
LATERAL VIEW explode(assessments) t AS assessment
