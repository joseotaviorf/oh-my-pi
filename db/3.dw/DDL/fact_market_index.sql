DROP TABLE IF EXISTS fact_market_index;
CREATE TABLE fact_market_index (
    sk_property BIGINT,
    sk_external_property BIGINT,
    sk_snapshot_date INT,
    sk_updated_on_date INT,
    business VARCHAR(200),
    advertiser_name VARCHAR(255),
    advertiser_type VARCHAR(255)
)