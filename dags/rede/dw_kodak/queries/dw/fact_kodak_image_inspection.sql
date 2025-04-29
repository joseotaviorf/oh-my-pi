WITH houses AS (
  SELECT
    id,
    id_external
  FROM
    datalake_ebdb_clean.house
  WHERE
    id_external IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_external ORDER BY dt_creation) = 1
)
SELECT
  im.id AS sk_image_inspection,
  im.id_photo AS sk_kodak_photo,
  im.id_duplicate,
  im.id_group,
  h.id AS id_house,
  l.id AS id_lead_3p,
  im.deduplication_hash,
  im.house_place,
  im.room_type,
  im.status,
  im.url,
  im.brightness,
  im.condition,
  im.framing,
  ig.framing_score,
  im.height,
  im.ordination,
  im.ratio,
  im.sharpness,
  im.width,
  im.is_approved,
  im.has_bonus_sharpness,
  im.has_fault_aspect_ratio,
  im.has_fault_brightness,
  im.has_fault_sharpness,
  im.has_red_flag_aspect_ratio,
  im.has_red_flag_casamineira,
  im.has_red_flag_compliance,
  im.has_red_flag_duplicate_image,
  im.has_red_flag_media_modification,
  im.has_red_flag_not_property,
  im.has_red_flag_sharpness,
  im.has_red_flag_size,
  im.has_red_flag_watermark,
  ia.has_balcony AS has_restb_amenity_balcony,
  ia.has_gym AS has_restb_amenity_gym,
  ia.has_pool AS has_restb_amenity_pool,
  ia.has_sauna AS has_restb_amenity_sauna,
  ia.has_sports_court AS has_restb_amenity_sports_court,
  ia.has_toy_library AS has_restb_amenity_toy_library,
  ia.has_unobstructed_view AS has_restb_amenity_unobstructed_view,
  ia.has_walk_in_closet AS has_restb_amenity_walk_in_closet,
  im.ts_created,
  im.ts_updated,
  NOW() AS ts_load
FROM
  datalake_kodak_clean.image_inspection AS im
INNER JOIN
  datalake_kodak_clean.image_inspection_group AS ig
    ON ig.id = im.id_group
LEFT JOIN
  houses AS h
    ON (ig.external_domain = 'LEAD3P' AND ig.id_external_domain = h.id_external
          OR ig.external_domain != 'LEAD3P' AND ig.id_external_domain = h.id
        )
LEFT JOIN
  datalake_brokers_supply_processor.lead_3p AS l
    ON ig.id_external_domain = l.uuid_lead
    AND ig.external_domain = 'LEAD3P'
    AND (ig.external_domain = 'LEAD3P' AND ig.id_external_domain = h.id_external
          OR ig.external_domain != 'LEAD3P' AND ig.id_external_domain = h.id
        )
LEFT JOIN
  datalake_kodak.image_inspection_amenities AS ia
    ON ia.id_house = h.id
    OR (ia.id_house IS NULL AND ia.id_lead_3p = l.id)