DROP TABLE IF EXISTS sale.fact_listing_price_changes;
CREATE TABLE sale.fact_listing_price_changes (
    sk_price_change BIGINT,
    sk_house BIGINT,
    sk_user_revision BIGINT,
    sk_owner BIGINT,
    sk_region BIGINT,
    sk_price_started_date BIGINT, 
    sk_price_ended_date BIGINT, 
    status_history VARCHAR,
    price BIGINT,
    previous_price BIGINT,
    previous_price_variation FLOAT,
    is_last_price BOOLEAN,
    is_first_price BOOLEAN,
    change_type VARCHAR,
    change INT, 
    days_with_pricing_scheme BIGINT,
    min_predicted_price BIGINT,
    p30_predicted_price BIGINT,
    predicted_price BIGINT,
    p70_predicted_price BIGINT,
    max_predicted_price BIGINT,
    predict_certainty VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE sale.fact_listing_price_changes OWNER TO airflow;