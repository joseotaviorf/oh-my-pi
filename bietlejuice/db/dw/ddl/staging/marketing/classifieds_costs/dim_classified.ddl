DROP TABLE if EXISTS staging.dim_classified;
CREATE TABLE if NOT EXISTS staging.dim_classified (
    sk_classified VARCHAR(100),
    name VARCHAR(100),
    ts_load timestamp
);