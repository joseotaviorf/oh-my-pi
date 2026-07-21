SELECT
  dashboard_id AS id_dashboard,
  business_group_id AS id_business_group,
  meeting_id AS id_meeting,
  person_id AS id_person,
  assignment_id AS id_assignment,
  pot_rt_lvl_id AS id_potential_rating_level,
  pot_calib_rt_lvl_id AS id_potential_rating_level_calibrated,
  risk_loss_rt_lvl_id AS id_risk_loss_rating_level,
  risk_loss_calib_rt_lvl_id AS id_risk_loss_rating_level_calibrated,

  extn_metric_value3 AS id_metric_value_3,
  extn_metric_calib_value3 AS id_metric_calibrated_value_3,
  extn_metric_value4 AS id_metric_value_4,
  extn_metric_calib_value4 AS id_metric_calibrated_value_4,
  extn_metric_value5 AS id_metric_value_5,
  extn_metric_calib_value5 AS id_metric_calibrated_value_5,
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
  datalake_pin_hr_review_raw.hrr_dashboards