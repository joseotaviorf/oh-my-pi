DROP TABLE IF EXISTS casa_mineira_portal.dim_house;
CREATE TABLE IF NOT EXISTS casa_mineira_portal.dim_house (
    sk_house INT PRIMARY KEY,
    sk_address INT,
    sk_real_estate_agency INT,
    sk_condo INT,
    sk_neighborhood INT,
    sk_type INT,
    id_house INT,
    goal VARCHAR(7),
    price FLOAT,
    address VARCHAR(255),
    zip_code VARCHAR,
    lat FLOAT,
    lng FLOAT,
    is_duplicated BOOLEAN,
    ts_created TIMESTAMP,
    ts_disabled TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE casa_mineira_portal.dim_house OWNER TO databricks;
