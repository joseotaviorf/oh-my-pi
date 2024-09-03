-- This DDL was created because the query for this table is self-referential in order to create the Primary Key.
-- Therefore, we need to have the empty table created manually before the query runs.
CREATE TABLE dw_data_quality.dim_validation_status (
    sk_validation_status BIGINT GENERATED ALWAYS AS IDENTITY,
    validation_status STRING
) USING DELTA LOCATION 's3://5a-dw-prod/data_quality/dim_validation_status'
