DROP TABLE if EXISTS marketing.dim_criteo_campaign;
CREATE TABLE if NOT EXISTS marketing.dim_criteo_campaign (
    sk_criteo_campaign INTEGER,
    campaign_name VARCHAR(65535),
)
;