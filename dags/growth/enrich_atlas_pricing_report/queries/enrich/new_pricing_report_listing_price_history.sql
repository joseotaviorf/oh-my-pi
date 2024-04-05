WITH listing_price_history AS (
SELECT
    NOW() AS ts_event,
    id_house::BIGINT,
    business_context::STRING,
    dt_price_updated::DATE,
    price::FLOAT,
    status::STRING
FROM
    datalake_atlas_pricing_report.status_history_house_listing
UNION
SELECT
    NOW() AS ts_event,
    id_house::BIGINT,
    business_context::STRING,
    dt_price_updated::DATE,
    price::FLOAT,
    status::STRING
FROM
  datalake_atlas_pricing_report.status_history_house_negotiation
UNION
SELECT
    NOW() AS ts_event,
    id_house::BIGINT,
    business_context::STRING,
    dt_price_updated::DATE,
    price::FLOAT,
    status::STRING
FROM
  datalake_atlas_pricing_report.status_history_house_price_change
UNION
SELECT
    NOW() AS ts_event,
    id_house::BIGINT,
    business_context::STRING,
    dt_price_updated::DATE,
    price::FLOAT,
    status::STRING
FROM
  datalake_atlas_pricing_report.status_history_house_unpublished
)
SELECT
    ts_event,
    MONOTONICALLY_INCREASING_ID() AS id,
    id_house,
    business_context,
    dt_price_updated,
    price,
    status
FROM
  listing_price_history
