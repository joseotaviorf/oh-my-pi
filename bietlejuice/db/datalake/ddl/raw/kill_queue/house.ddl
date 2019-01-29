drop table if exists datalake_raw.killqueue_house;

CREATE EXTERNAL TABLE datalake_raw.`killqueue_house`(
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
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' LOCATION 's3://5a-datalake/raw/kill_queue/house/';