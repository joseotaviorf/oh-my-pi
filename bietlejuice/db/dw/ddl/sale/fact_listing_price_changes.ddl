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
    predict_certainty VARCHAR,
    change_type VARCHAR,
    change INT, 
    days_with_pricing_scheme INT,
    price INT,
    previous_price INT,
    previous_price_variation FLOAT,
    first_price_variation FLOAT,
    min_predicted_price INT,
    p30_predicted_price INT,
    predicted_price INT,
    p70_predicted_price INT,
    max_predicted_price INT,
    is_last_price BOOLEAN,
    is_first_price BOOLEAN,
    ts_load TIMESTAMP
);
ALTER TABLE sale.fact_listing_price_changes OWNER TO airflow;