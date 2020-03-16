select
  cast(sk_region as integer) as sk_region,
  cast(name as varchar) as name,
	cast(city_name as varchar) as city_name,
  cast(updated_rented_apartment_households as integer) as updated_rented_apartment_households,
  cast(ongoing_listings as integer) as ongoing_listings,
  cast(ongoing_contracts as integer) as ongoing_contracts,
  cast(total_5A_presence as integer) as total_5A_presence,
  round(cast(ol_share as float),2) as ol_share,
  round(cast(oc_share as float),2) as oc_share,
  round(cast(total_5A_share as float),2) as total_5A_share,
  CURRENT_TIMESTAMP AS carto_ts_load
from datamarts.market_share_by_sk_region
