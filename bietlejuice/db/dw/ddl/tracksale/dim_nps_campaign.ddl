DROP TABLE IF EXISTS tracksale.dim_nps_campaign;
CREATE TABLE IF NOT EXISTS tracksale.dim_nps_campaign (
    sk_nps_campaign VARCHAR PRIMARY KEY,
    name VARCHAR,
    main_channel VARCHAR,
    business_context VARCHAR,
    customer_journey VARCHAR,
    purpose VARCHAR,
    customer_type VARCHAR,
    partner_name VARCHAR,
    metric_group VARCHAR,
    ts_created TIMESTAMP,
    ts_load TIMESTAMP
)
