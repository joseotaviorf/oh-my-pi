SELECT
  id,
  cast(date(ts_created) as date) as created_at,
  cast(date(ts_updated) as date) as updated_at,
  version,
  id_main as main_id,
  street_address,
  house_number,
  complement,
  city,
  state,
  is_reservation_allowed as reservation_allowed,
  rent_price,
  floor,
  reservation_fee,
  id_region as region_id,
  id_owner as owner_id
FROM house;
