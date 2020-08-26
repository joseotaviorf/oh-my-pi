DROP TABLE staging.dim_user_affiliate;

CREATE TABLE staging.dim_user_affiliate (
    sk_user_affiliate BIGINT NOT NULL,
    id_user_affiliate BIGINT,
    sk_user_indicated_by BIGINT,
    ts_joined_program TIMESTAMP,
    is_active BOOLEAN,
    ts_updated TIMESTAMP,
    ts_created TIMESTAMP,
    origin VARCHAR(255),
    type VARCHAR(255),
    marketing_city_group VARCHAR(255),
    regional VARCHAR(255),
    is_realstate_agent BOOLEAN,
    is_photographer BOOLEAN,
    tracking_source VARCHAR(255),
    tracking_medium VARCHAR(255),
    tracking_campaign VARCHAR(255),
    tracking_content VARCHAR(255),
    tracking_term VARCHAR(255),
    tracking_platform VARCHAR(255),
    tracking_device_type VARCHAR(255),
    tracking_country VARCHAR(255),
    tracking_state VARCHAR(255),
    tracking_city VARCHAR(255),
    mkt_origin VARCHAR(255),
    mkt_channel VARCHAR(255),
    mkt_medium VARCHAR(255),
    mkt_source VARCHAR(255),
    ts_load TIMESTAMP
)
WITH (oids = false);
