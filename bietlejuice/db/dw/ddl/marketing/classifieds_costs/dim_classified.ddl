DROP TABLE if EXISTS marketing.dim_classified;
CREATE TABLE if NOT EXISTS marketing.dim_classified (
    sk_classified SMALLINT,
    name VARCHAR(100),
    dt_cost DATE,
    ts_load timestamp
)
;