DROP TABLE IF EXISTS janus.fact_house_listing_status;

CREATE TABLE IF NOT EXISTS janus.fact_house_listing_status (
  sk_house_listing BIGINT,
  sk_region BIGINT,
  sk_first_publication_date BIGINT,
  sk_status_start_date BIGINT,
  sk_status_end_date BIGINT,
  ts_status_start TIMESTAMP,
  ts_status_end TIMESTAMP,
  status_history VARCHAR,
  status_change_reason VARCHAR(5000),
  is_last_status_of_day BOOLEAN,
  ts_load TIMESTAMP
);

ALTER TABLE janus.fact_house_listing_status OWNER TO airflow;