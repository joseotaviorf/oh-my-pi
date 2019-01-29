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
  cast(floor as CHAR) as floor,
  reservation_fee,
  cast(region_id as CHAR) as region_id,
  cast(owner_id as CHAR) as owner_id
FROM house;
