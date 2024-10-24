SELECT
  id,
  externaldomainid AS id_external_domain,
  externaldomain AS external_domain,
  status,
  bathrooms,
  bedrooms,
  score,
  approval_score_threshold,
  property_condition,
  framing_score,
  num_internal_photos,
  images_per_room,
  total_faults,
  approved AS is_approved,
  bonus_good_sharpness AS has_bonus_good_sharpness,
  bonus_aspect_ratio AS has_bonus_aspect_ratio,
  bonus_images_per_room AS has_bonus_images_per_room,
  bonus_view AS has_bonus_view,
  bonus_external AS has_bonus_external,
  red_flags AS has_red_flags,
  red_flag_images_per_room AS has_red_flag_images_per_room,
  red_flag_property_condition AS has_red_flag_property_condition,
  red_flag_primary_risk AS has_red_flag_primary_risk,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_kodak_raw.image_inspection_group
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
