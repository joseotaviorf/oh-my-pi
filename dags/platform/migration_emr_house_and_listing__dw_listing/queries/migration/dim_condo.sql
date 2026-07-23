SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  c.id AS sk_condo,
  c.id AS id_condo,
  NULLIF(c.neighborhood, '') as neighborhood,
  c.zipcode,
  c.city,
  NULLIF(c.address, '') as address,
  CAST(c.lat AS DECIMAL(10,7)) AS lat,
  CAST(c.lng AS DECIMAL(10,7)) AS lng,
  NULLIF(c.name, '') as name,
  c.number,
  date_trunc('DD', c.ts_created) AS ts_created, -- [ODS] removing the time part to match ODS-DW table
  date_trunc('DD', c.ts_updated) AS ts_updated, -- [ODS] removing the time part to match ODS-DW table
  NOW() as ts_load
from datalake_ebdb_clean.condo c