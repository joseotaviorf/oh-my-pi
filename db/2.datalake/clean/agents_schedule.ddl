DROP TABLE IF EXISTS datalake_clean.agents_schedule;
CREATE TABLE IF NOT EXISTS datalake_clean.agents_schedule (
 row_number INT,
 agent_user_id INT,
 available_date DATE,
 region_id INT,
 region_name STRING,
 slot_id INT,
 slot_start STRING,
 slot_end STRING,
 slot_available BOOLEAN,
 slot_status STRING,
 timestamp TIMESTAMP
   ) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/agents_schedule'
;