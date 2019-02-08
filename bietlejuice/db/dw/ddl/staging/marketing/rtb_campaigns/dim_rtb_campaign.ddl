DROP TABLE if EXISTS staging.dim_rtb_campaign;
CREATE TABLE if NOT EXISTS staging.dim_rtb_campaign (
    sk_rtb_campaign INTEGER,
    id_campaign INTEGER,
    status VARCHAR(100),
    hash VARCHAR(300),
    url VARCHAR(300)
)
;