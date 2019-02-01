DROP TABLE staging.dim_user_affiliate;

CREATE TABLE staging.dim_user_affiliate (
    sk_affiliate BIGINT NOT NULL,
    id_affiliate BIGINT,
    ts_joined_program TIMESTAMP,
    category VARCHAR(255),
    work_city VARCHAR(255),
    is_active BOOLEAN,
    ts_updated TIMESTAMP,
    ts_created TIMESTAMP,
    creci_number VARCHAR(255),
    origin VARCHAR(255),
    type VARCHAR(255),
    ts_load TIMESTAMP
)
WITH (oids = false);
