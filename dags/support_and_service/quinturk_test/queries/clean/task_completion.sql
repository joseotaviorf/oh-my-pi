WITH extract_quinturk_task_completion_result AS (
  SELECT
    id,
    task_id AS id_task,
    parent_annotation_id AS id_parent_annotation,
    parent_prediction_id AS id_parent_prediction,
    completed_by_id AS id_completed_by,
    last_created_by_id AS id_last_created_by,
    prediction,
    result,
    lead_time,
    result_count,
    last_action,
    ground_truth AS is_ground_truth,
    was_cancelled,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day,
    from_json(
      result,
      'ARRAY<STRUCT<
    id: STRING,
    type: STRING,
    origin: STRING,
    from_name: STRING,
    value: STRUCT<choices: ARRAY<STRING>, text: ARRAY<STRING>>
    >>'
    ) AS extracted_result
  FROM
    datalake_quinturk_test_raw.task_completion
)
SELECT
  id,
  id_task,
  id_parent_annotation,
  id_parent_prediction,
  id_completed_by,
  id_last_created_by,
  extracted_result.id AS id_input,
  extracted_result.type AS input_type,
  extracted_result.origin AS inpput_origin,
  extracted_result.from_name AS input_document_name,
  prediction,
  result,
  lead_time,
  result_count,
  last_action,
  extracted_result.value AS input_value,
  is_ground_truth,
  was_cancelled,
  ts_created,
  ts_updated,
  op_cdc,
  ts_cdc_transaction,
  ts_database_transaction
  year,
  month,
  day
FROM
  extract_quinturk_task_completion_result

