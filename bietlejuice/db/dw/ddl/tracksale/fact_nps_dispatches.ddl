DROP TABLE IF EXISTS tracksale.fact_nps_dispatches;
CREATE TABLE IF NOT EXISTS tracksale.fact_nps_dispatches (
    sk_nps_dispatch VARCHAR(500) PRIMARY KEY,
    sk_nps_dispatch_lot VARCHAR(20),
    sk_nps_campaign VARCHAR(50),
    sk_nps_customer VARCHAR(400),
    sk_user BIGINT,
    sk_personal_document VARCHAR(25),
    sk_nps_answer BIGINT,
    sk_house_listing BIGINT,
    sk_booking BIGINT,
    sk_tta VARCHAR(50),
    sk_offer VARCHAR(50),
    sk_contract BIGINT,
    sk_last_rent_event BIGINT,
    sk_last_rent_event_type INTEGER,
    sk_created_date BIGINT,
    sk_sent_date BIGINT,
    sk_answered_date BIGINT,
    sk_last_rent_event_date BIGINT,
    score SMALLINT,
    minutes_response_time DECIMAL(27,2),
    dispatch_status VARCHAR(255),
    city VARCHAR(255),
    is_survey_opened BOOLEAN,
    is_pending_survey BOOLEAN,
    is_answered BOOLEAN,
    has_comment BOOLEAN,
    is_customer_identified BOOLEAN,
    ts_load TIMESTAMP
);
CALL grant_all_permissions_on_schema('tracksale');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA tracksale TO GROUP etl;
GRANT ALL ON SCHEMA tracksale TO GROUP ETL;
ALTER TABLE tracksale.fact_nps_dispatches owner TO airflow;