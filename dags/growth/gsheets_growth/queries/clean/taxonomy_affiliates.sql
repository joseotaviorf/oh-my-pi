SELECT
  id,
  affiliate_type,
  tracking_source,
  tracking_medium,
  tracking_campaign,
  mkt_origin,
  mkt_channel,
  mkt_medium,
  mkt_source
FROM (
  SELECT
    COALESCE(id, '') AS id,
    COALESCE(affiliate_type, '') AS affiliate_type,
    COALESCE(tracking_source, '') AS tracking_source,
    COALESCE(tracking_medium, '') AS tracking_medium,
    COALESCE(tracking_campaign, '') AS tracking_campaign,
    COALESCE(mkt_origin, '') AS mkt_origin,
    COALESCE(mkt_channel, '') AS mkt_channel,
    COALESCE(mkt_medium, '') AS mkt_medium,
    COALESCE(mkt_source, '') AS mkt_source,
    ROW_NUMBER() OVER (PARTITION BY COALESCE(affiliate_type, ''), COALESCE(tracking_medium, ''), COALESCE(tracking_source, ''), COALESCE(tracking_campaign, '') ORDER BY ID) AS _w
  FROM datalake_gsheets_raw.taxonomy_affiliates
) AS _t
WHERE
  _w = 1