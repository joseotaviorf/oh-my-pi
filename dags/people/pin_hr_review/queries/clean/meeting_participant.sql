SELECT
  business_group_id AS id_business_group,
  participant_person_id AS id_participant_person,
  meeting_id AS id_meeting,
  data_submission_status_code,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_hr_review_raw.hrr_meeting_participants
