DROP TABLE staging.dim_user_doorman;

CREATE TABLE staging.dim_user_doorman (
    sk_user_doorman BIGINT NOT NULL,
    id_user_doorman BIGINT,
    work_address VARCHAR(1024),
    work_street VARCHAR(255),
    work_house_number VARCHAR(255),
    work_neighbourhood VARCHAR(255),
    work_city VARCHAR(255),
    work_state VARCHAR(255),
    work_lat DECIMAL,
    work_lng DECIMAL,
    id_work_place VARCHAR(255),
    code VARCHAR(255),
    recruiter_name VARCHAR(255),
    subscription_source VARCHAR(255),
   id_occupation BIGINT,
    occupation_name VARCHAR(255),
    ts_updated TIMESTAMP,
    ts_created TIMESTAMP,
    ts_joined_program TIMESTAMP,
    sk_user_affiliate BIGINT,
    is_active BOOLEAN,
    ts_load TIMESTAMP
)
WITH (oids = false);
