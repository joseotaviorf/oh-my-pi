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
