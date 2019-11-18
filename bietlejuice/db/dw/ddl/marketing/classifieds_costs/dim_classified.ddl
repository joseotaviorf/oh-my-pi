DROP TABLE if EXISTS marketing.dim_classified;
CREATE TABLE if NOT EXISTS marketing.dim_classified (
    sk_classified VARCHAR(100) primary key,
    name VARCHAR(100),
    ts_load timestamp
);