drop table if exists public.condo;
CREATE TABLE public.condo (
  id BIGINT PRIMARY KEY,
  updated_in DATE,
  created_in DATE,
  neighborhood VARCHAR(200),
  zipcode VARCHAR(20),
  city VARCHAR(200),
  address VARCHAR(200),
  lat NUMERIC(10,7),
  lng NUMERIC(10,7),
  name VARCHAR(255),
  number VARCHAR(200),
  condo_manager_id BIGINT,
  rules TEXT
)
;