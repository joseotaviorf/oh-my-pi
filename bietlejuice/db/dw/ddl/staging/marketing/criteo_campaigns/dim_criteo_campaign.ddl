DROP TABLE if EXISTS staging.dim_criteo_campaign;
CREATE TABLE if NOT EXISTS staging.dim_criteo_campaign (
    sk_criteo_campaign INTEGER,
    id_campaign INTEGER,
    advertiser_name VARCHAR(100),
    campaign_name VARCHAR(100)
)
;