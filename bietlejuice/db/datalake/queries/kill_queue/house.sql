SELECT
  id,
  created_at,
  updated_at,
  version,
  main_id,
  street_address,
  house_number,
  complement,
  city,
  state,
  reservation_allowed,
  rent_price,
  floor,
  reservation_fee,
  region_id
FROM datalake_raw.killqueue_house;