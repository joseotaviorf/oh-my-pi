WITH extract_quinturk_task_data AS (
  SELECT
    id,
    project_id AS id_project,
    updated_by_id AS id_updated_by,
    file_upload_id AS id_file_upload,
    inner_id AS id_inner,
    total_annotations,
    cancelled_annotations,
    total_predictions,
    overlap,
    data,
    meta,
    is_labeled,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day,
    from_json(
      data,
      'STRUCT<
      cpf: STRING,
      name: STRING,
      id_proposal: STRING
    >'
    ) AS extracted_data
  FROM
    datalake_quinturk_raw.task
)
SELECT
  id,
  id_project,
  id_updated_by,
  id_file_upload,
  id_inner,
  extracted_data.id_proposal,
  total_annotations,
  cancelled_annotations,
  total_predictions,
  overlap,
  data,
  extracted_data.cpf AS proponent_cpf,
  extracted_data.name AS proponent_name,
  meta,
  is_labeled,
  ts_created,
  ts_updated,
  year,
  month,
  day
FROM
  extract_quinturk_task_data
