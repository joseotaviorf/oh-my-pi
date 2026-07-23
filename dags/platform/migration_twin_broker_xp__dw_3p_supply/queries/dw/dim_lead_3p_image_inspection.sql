SELECT
  ii.id AS sk_image_inspection,
  COALESCE(ii.id_duplicate, -1) AS sk_image_inspection_duplicated,
  l.id_lead_3p AS sk_lead_3p,
  ii.id_group,
  ii.deduplication_hash,
  ii.house_place,
  ii.status AS image_inspection_status,
  GET_JSON_OBJECT(p.metadata, '$.mimetype') AS photo_mime_type,
  GET_JSON_OBJECT(p.metadata, '$.order') AS photo_order,
  p.path AS photo_path,
  ii.room_type,
  ii.url,
  iig.approval_score_threshold,
  ii.brightness,
  ii.condition,
  ii.framing,
  iig.framing_score,
  ii.height,
  iig.images_per_room,
  iig.num_internal_photos,
  ii.ordination,
  iig.property_condition,
  ii.ratio,
  iig.score,
  ii.sharpness,
  iig.total_faults,
  ii.width,
  ROW_NUMBER() OVER (PARTITION BY l.id_lead_3p ORDER BY iig.ts_created) AS image_inspection_version,
  ii.is_approved,
  iig.has_bonus_aspect_ratio,
  iig.has_bonus_external,
  iig.has_bonus_good_sharpness,
  iig.has_bonus_images_per_room,
  ii.has_bonus_sharpness,
  iig.has_bonus_view,
  ii.has_fault_aspect_ratio,
  ii.has_fault_brightness,
  ii.has_fault_sharpness,
  iig.has_red_flags,
  ii.has_red_flag_aspect_ratio,
  ii.has_red_flag_casamineira,
  ii.has_red_flag_compliance,
  ii.has_red_flag_duplicate_image,
  iig.has_red_flag_images_per_room,
  ii.has_red_flag_media_modification,
  ii.has_red_flag_not_property,
  iig.has_red_flag_primary_risk,
  iig.has_red_flag_property_condition,
  ii.has_red_flag_sharpness,
  ii.has_red_flag_size,
  ii.has_red_flag_watermark,
  TRUE AS has_3p_access_control,
  ii.ts_created AS ts_image_inspection_created,
  iig.ts_created AS ts_image_inspection_group_created,
  ii.ts_updated AS ts_image_inspection_updated,
  iig.ts_updated AS ts_image_inspection_group_updated,
  CURRENT_TIMESTAMP() AS ts_load,
  ii.year,
  ii.month,
  ii.day
FROM
  datalake_kodak_clean.image_inspection AS ii
INNER JOIN
  datalake_kodak_clean.image_inspection_group AS iig
  ON iig.id = ii.id_group
INNER JOIN
  datalake_kodak_clean.photo AS p
  ON p.id = ii.id_photo
INNER JOIN
  datalake_3p_supply.lead_3p AS l
  ON l.uuid_lead = iig.id_external_domain
  AND iig.external_domain = 'LEAD3P'
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY l.uuid_lead ORDER BY l.id_lead_3p DESC) = 1
