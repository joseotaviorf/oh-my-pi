-- This DDL was created because the query for this table is self-referential in order to create the Primary Key.
-- Therefore, we need to have the empty table created manually before the query runs.
CREATE TABLE datalake_ebdb_pricing.listing_prediction_changes (
    id_prediction_change BIGINT GENERATED ALWAYS AS IDENTITY,
    id_house BIGINT,
    id_house_listing BIGINT,
    id_revision INT,
    business_context STRING,
    calculator_min_price INT,
    calculator_p30_price INT,
    calculator_price INT,
    calculator_p70_price INT,
    calculator_max_price INT,
    calculator_certainty STRING,
    is_last_prediction_of_day BOOLEAN,
    ts_calculator_result_started TIMESTAMP,
    ts_calculator_result_ended TIMESTAMP
) USING DELTA LOCATION 's3://5a-datalake-prod/enrich/ebdb_pricing/listing_prediction_changes'
