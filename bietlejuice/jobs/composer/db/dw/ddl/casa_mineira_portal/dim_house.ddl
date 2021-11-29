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
    address VARCHAR(255),
    zip_code VARCHAR(9),
    lat FLOAT,
    lng FLOAT,
    ts_created TIMESTAMP,
    ts_disabled TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE casa_mineira_portal.dim_house OWNER TO databricks;
