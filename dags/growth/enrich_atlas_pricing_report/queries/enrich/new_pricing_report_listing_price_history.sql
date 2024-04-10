WITH listing_price_history AS (
    SELECT
        NOW() AS ts_event,
        id_house::BIGINT,
        business_context::STRING,
        ts_status_started::DATE,
        price::FLOAT,
        status::STRING
    FROM
        datalake_atlas_pricing_report.status_history_house_listing
    UNION
    SELECT
        NOW() AS ts_event,
        id_house::BIGINT,
        business_context::STRING,
        ts_status_started::DATE,
        price::FLOAT,
        status::STRING
    FROM
      datalake_atlas_pricing_report.status_history_house_negotiation
    UNION
    SELECT
        NOW() AS ts_event,
        id_house::BIGINT,
        business_context::STRING,
        ts_status_started::DATE,
        price::FLOAT,
        status::STRING
    FROM
      datalake_atlas_pricing_report.status_history_house_price_change
)
SELECT
    UNIX_TIMESTAMP(NOW()) AS ts_event,
    MONOTONICALLY_INCREASING_ID() AS id,
    id_house,
    business_context::STRING,
    UNIX_TIMESTAMP(ts_status_started, 'yyyy-MM-dd') AS ts_status_started,
    price,
    status
FROM
  listing_price_history
