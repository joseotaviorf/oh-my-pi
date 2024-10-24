SELECT
  id,
  id_group,
  business_context,
  red_flags AS has_red_flags,
  bonus_good_sharpness AS has_bonus_good_sharpness,
  bonus_aspect_ratio AS has_bonus_aspect_ratio,
  bonus_images_per_room AS has_bonus_images_per_room,
  bonus_view AS has_bonus_view,
  bonus_external AS has_bonus_external,
  red_flag_images_per_room AS has_red_flag_images_per_room,
  red_flag_property_condition AS has_red_flag_property_condition,
  red_flag_primary_risk AS has_red_flag_primary_risk,
  approved AS is_approved,
  total_faults,
  score,
  approval_score_threshold,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_kodak_raw.image_inspection_group_result
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
