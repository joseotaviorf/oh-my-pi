drop table if exists datalake_clean.killqueue_house;

CREATE EXTERNAL TABLE datalake_clean.`killqueue_house`(
  `id`                  string,
  `created_at`          string,
  `updated_at`          string,
  `version`             string,
  `main_id`             string,
  `street_address`      string,
  `house_number`        string,
  `complement`          string,
  `city`                string,
  `state`               string,
  `reservation_allowed` string,
  `rent_price`          string,
  `floor`               string,
  `reservation_fee`     string,
  `region_id`           string,
  `owner_id`            string
)
STORED AS PARQUET LOCATION 's3://5a-datalake/clean/kill_queue/house/';