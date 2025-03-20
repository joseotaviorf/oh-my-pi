SELECT
  id,
  hubs_id AS id_hubs,
  name,
  mobile_phone,
  phone,
  email,
  address,
  city,
  state,
  label,
  type,
  latitude,
  longitude,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sales_flow_raw.notary_office