DROP TABLE IF EXISTS datalake_clean.property_status_full_history;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.property_status_full_history (
 date DATE,
 id BIGINT,
 status STRING,
 status_date DATE,
 status_time TIMESTAMP,
 status_history STRING,
 current_status STRING,
 datePublication TIMESTAMP,
 published SMALLINT,
 rnk BIGINT,
 first_status_date DATE,
 last_status_date DATE,
 next_status_date DATE,
 next_status_time TIMESTAMP,
 next_status STRING,
 diff_status_time STRING,
 pub_at_least_min_time_flag BOOLEAN,
 distinct_status_flag BOOLEAN,
 last_position_date_flag BOOLEAN,
 all_status_date_position_flag BOOLEAN
 ) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/property_status_full_history'
;