SELECT
    COALESCE(id, '') AS id,
    COALESCE(affiliate_type, '') AS affiliate_type,
    COALESCE(tracking_source, '') AS tracking_source,
    COALESCE(tracking_medium, '') AS tracking_medium,
    COALESCE(tracking_campaign, '') AS tracking_campaign,
    COALESCE(mkt_origin, '') AS mkt_origin,
    COALESCE(mkt_channel, '') AS mkt_channel,
    COALESCE(mkt_medium, '') AS mkt_medium,
    COALESCE(mkt_source, '') AS mkt_source
FROM
    datalake_gsheets_raw.taxonomy_affiliates
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY affiliate_type, tracking_medium, tracking_source, tracking_campaign ORDER BY ID) = 1