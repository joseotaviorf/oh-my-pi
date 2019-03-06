DROP TABLE staging.dim_user_affiliate;

CREATE TABLE staging.dim_user_affiliate (
    sk_user_affiliate BIGINT NOT NULL,
    id_user_affiliate BIGINT,
    ts_joined_program TIMESTAMP,
    category VARCHAR(255),
    work_city VARCHAR(255),
    is_active BOOLEAN,
    ts_updated TIMESTAMP,
    ts_created TIMESTAMP,
    creci_number VARCHAR(255),
    origin VARCHAR(255),
    type VARCHAR(255),
    is_inspector BOOLEAN,
    is_realstate_agent BOOLEAN,
    is_photographer BOOLEAN,
    tracking_source VARCHAR(255),
    tracking_medium VARCHAR(255),
    tracking_campaign VARCHAR(255),
    tracking_platform VARCHAR(255),
    tracking_device_type VARCHAR(255),
    tracking_country VARCHAR(255),
    tracking_state VARCHAR(255),
    tracking_city VARCHAR(255),
    ts_load TIMESTAMP
)
WITH (oids = false);
