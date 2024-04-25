WITH listing_price_history AS (
  SELECT
    NOW() AS ts_event,
    id_house::BIGINT,
    version::BIGINT,
    business_context::STRING,
    ts_status_started::TIMESTAMP,
    price::FLOAT,
    status::STRING,
    status_reason::STRING
  FROM
    datalake_atlas_pricing_report.status_history_house_listing
  UNION
  SELECT
    NOW() AS ts_event,
    id_house::BIGINT,
    version::BIGINT,
    business_context::STRING,
    ts_status_started::TIMESTAMP,
    price::FLOAT,
    status::STRING,
    status_reason::STRING
  FROM
    datalake_atlas_pricing_report.status_history_house_negotiation
  UNION
  SELECT
    NOW() AS ts_event,
    id_house::BIGINT,
    version::BIGINT,
    business_context::STRING,
    ts_status_started::TIMESTAMP,
    price::FLOAT,
    status::STRING,
    status_reason::STRING
  FROM
    datalake_atlas_pricing_report.status_history_house_price_change
)
SELECT
  DATE_FORMAT(ts_event, 'yyyy-MM-dd\'T\'HH:mm:ss') AS ts_event,
  MONOTONICALLY_INCREASING_ID() AS id,
  id_house,
  version,
  business_context::STRING,
  price,
  status,
  status_reason,
  DATE_FORMAT(ts_status_started, 'yyyy-MM-dd\'T\'HH:mm:ss') AS ts_status_started
FROM
  listing_price_history
