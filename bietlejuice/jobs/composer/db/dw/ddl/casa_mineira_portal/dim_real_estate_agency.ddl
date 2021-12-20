DROP TABLE IF EXISTS casa_mineira_portal.dim_real_estate_agency;
CREATE TABLE IF NOT EXISTS casa_mineira_portal.dim_real_estate_agency (
    sk_real_estate_agency INT PRIMARY KEY,
    sk_real_estate_agency_created_date INT,
    sk_real_estate_agency_disabled_date INT,
    id_real_estate_agency INT,
    real_estate_agency_name VARCHAR(255),
    real_estate_agency_full_name VARCHAR(255),
    uf VARCHAR(255),
    city VARCHAR(255),
    neighborhood VARCHAR(255),
    address VARCHAR(255),
    zip_code VARCHAR(9),
    lat FLOAT,
    lng FLOAT,
    website VARCHAR(255),
    integration_format VARCHAR(255),
    notification_type VARCHAR(255),
    is_juridical_person BOOLEAN,
    is_natural_person BOOLEAN,
    ts_real_estate_agency_created TIMESTAMP,
    ts_real_estate_agency_disabled TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE casa_mineira_portal.dim_real_estate_agency OWNER TO databricks;
