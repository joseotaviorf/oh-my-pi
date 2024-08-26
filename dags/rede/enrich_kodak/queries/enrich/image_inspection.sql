SELECT
  im.id,
  im.id_photo,
  im.id_group,
  im.id_duplicate,
  h.id AS id_house,
  l.id AS id_lead_3p,
  im.deduplication_hash,
  im.url,
  im.house_place,
  im.room_type,
  im.status,
  im.description,
  CASE
    WHEN ig.framing_score BETWEEN 0.0 AND 0.3 THEN 'T0-30%'
    WHEN ig.framing_score BETWEEN 0.3 AND 0.6 THEN 'T30-60%'
    WHEN ig.framing_score >= 0.6 THEN 'T60+%'
  END AS framing_score_cluster,
  im.width,
  im.height,
  im.ratio,
  im.sharpness,
  im.brightness,
  im.framing,
  im.condition,
  im.ordination,
  ig.framing_score,
  im.is_approved,
  im.has_red_flag_watermark,
  im.has_red_flag_compliance,
  im.has_red_flag_size,
  im.has_red_flag_sharpness,
  im.has_red_flag_not_property,
  im.has_red_flag_aspect_ratio,
  im.has_red_flag_casamineira,
  im.has_red_flag_media_modification,
  im.has_red_flag_duplicate_image,
  im.has_fault_brightness,
  im.has_fault_sharpness,
  im.has_fault_aspect_ratio,
  im.has_bonus_sharpness,
  im.ts_created,
  im.ts_updated
FROM
  datalake_kodak_clean.image_inspection AS im
INNER JOIN
  datalake_kodak_clean.image_inspection_group AS ig
    ON ig.id = im.id_group
LEFT JOIN
  datalake_ebdb_clean.house AS h
    ON (ig.external_domain = 'LEAD3P' AND ig.id_external_domain = h.id_external
          OR ig.external_domain != 'LEAD3P' AND ig.id_external_domain = h.id
        )
LEFT JOIN
  datalake_brokers_supply_processor_clean.lead_3p AS l
    ON ig.id_external_domain = l.uuid_lead
    AND ig.external_domain = 'LEAD3P'
    AND (ig.external_domain = 'LEAD3P' AND ig.id_external_domain = h.id_external
          OR ig.external_domain != 'LEAD3P' AND ig.id_external_domain = h.id
        )