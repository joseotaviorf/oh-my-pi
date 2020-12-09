DROP TABLE IF EXISTS quintoandar.dim_listing_owner;
CREATE TABLE quintoandar.dim_listing_owner (
  sk_listing_owner BIGINT PRIMARY KEY,
  name VARCHAR,
  personal_document VARCHAR,
  email VARCHAR,
  phone VARCHAR,
  address_street VARCHAR,
  address_number VARCHAR,
  address_complement VARCHAR,
  address_neighborhood VARCHAR,
  city VARCHAR,
  uf VARCHAR,
  address_postal_code VARCHAR,
  is_b2b BOOLEAN, 
  has_rent_listings BOOLEAN,
  has_sale_listings BOOLEAN,
  has_sms_notifications_enabled BOOLEAN,
  has_whatsapp_notifications_enabled BOOLEAN,
  dt_birth DATE,
  ts_user_signed_up TIMESTAMP,
  ts_first_house_created TIMESTAMP,
  ts_load TIMESTAMP
);

ALTER TABLE quintoandar.dim_listing_owner OWNER TO airflow;
