SELECT
  cast(id as char) as id,
  cast(created_at as char) as created_at,
  cast(updated_at as char) as updated_at,
  cast(version as char) as version,
  cast(main_id as char) as main_id,
  street_address,
  house_number,
  complement,
  city,
  state,
  cast(reservation_allowed as UNSIGNED) as reservation_allowed,
  cast(rent_price as char) as rent_price,
  cast(floor as CHAR) as floor,
  cast(reservation_fee as char) as reservation_fee,
  cast(region_id as CHAR) as region_id,
  cast(owner_id as CHAR) as owner_id
FROM house;
