-- This DDL was created because the query for this table is self-referential in order to create the Primary Key.
-- Therefore, we need to have the empty table created manually before the query runs.
CREATE TABLE datalake_ebdb_pricing.listing_price_change (
    id_price_change BIGINT GENERATED ALWAYS AS IDENTITY,
    id_house BIGINT,
    id_house_listing BIGINT,
    id_user_revision BIGINT,
    id_revision INT,
    business_context STRING,
    change_reason STRING,
    price INT,
    previous_price INT,
    last_price_variation DOUBLE,
    first_price_variation DOUBLE,
    change_type STRING,
    change_number INT,
    days_with_pricing_scheme INT,
    is_first_price BOOLEAN,
    is_last_price BOOLEAN,
    is_last_price_of_day BOOLEAN,
    ts_price_started TIMESTAMP,
    ts_price_ended TIMESTAMP
) USING DELTA LOCATION 's3://5a-datalake-prod/enrich/ebdb_pricing/listing_price_change'
