DROP TABLE IF EXISTS casa_mineira_portal.dim_house_feature;
CREATE TABLE IF NOT EXISTS casa_mineira_portal.dim_house_feature (
    sk_house INT,
    sk_attribute INT,
    sk_attribute_type INT,
    sk_attribute_created_date INT,
    sk_house_attribute_created_date INT,
    sk_house_attribute_deleted_date INT,
    attribute_name VARCHAR(50),
    attribute_full_name VARCHAR(50),
    attribute_type_name VARCHAR(50),
    attribute_type_full_name VARCHAR(50),
    ts_attribute_created TIMESTAMP,
    ts_house_attribute_created TIMESTAMP,
    ts_house_attribute_deleted TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE casa_mineira_portal.dim_house_feature OWNER TO databricks;
