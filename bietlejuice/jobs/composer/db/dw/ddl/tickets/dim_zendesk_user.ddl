DROP TABLE IF EXISTS tickets.dim_zendesk_user;
CREATE TABLE IF NOT EXISTS tickets.dim_zendesk_user (
    sk_zendesk_user BIGINT PRIMARY KEY,
    url_user VARCHAR (65535),
    name VARCHAR (65535),
    alias VARCHAR (65535),
    email VARCHAR,
    phone VARCHAR,
    time_zone VARCHAR,
    locale VARCHAR,
    tags VARCHAR,
    role VARCHAR,
    is_active BOOLEAN,
    is_shared_phone_number BOOLEAN,
    ts_last_login TIMESTAMP,
    ts_created TIMESTAMP,
    ts_created_local TIMESTAMP,
    ts_updated TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE tickets.dim_zendesk_user OWNER TO airflow;
