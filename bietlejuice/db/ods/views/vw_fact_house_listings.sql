drop view if exists vw_fact_house_listings;
create or replace view vw_fact_house_listings as
select
  ((i.id || '00') || coalesce(pl.version, 1))::bigint as sk_house_listing,
  coalesce(i.usuario_id, -1) as sk_owner,
  coalesce(i.regiao_id, -1) as sk_region,
  coalesce(i.usuario_que_cadastrou_id, -1) as sk_user_registration,
  coalesce(c.id, -1) as sk_contract,
  (date_part('epoch', c.ts_signature - pl.min_version_time) / 86400)::int8 as days_first_listing_to_contract_signed,
  (date_part('epoch', pl.de_publication_date - pl.min_version_time) / 86400)::int8 as days_listing_to_depublication,
  coalesce(pl.nr_renting::bigint, 0) as nr_renting,
  now()::timestamp as ts_load
from house i
left join house_listing pl
  on pl.id = i.id
left join contract c
  on c.id = pl.contract_id
;