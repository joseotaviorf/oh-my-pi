drop view if exists vw_fact_house_listings;
create or replace view vw_fact_house_listings as
select
  ((h.id || '00') || coalesce(pl.version, 1))::bigint as sk_house_listing,
  coalesce(h.usuario_id, -1) as sk_owner,
  coalesce(h.regiao_id, -1) as sk_region,
  coalesce(h.usuario_que_cadastrou_id, -1) as sk_user_registration,
  coalesce(c.id, -1) as sk_contract,
  coalesce(cd.id, -1) as sk_condo,
  (date_part('epoch', c.ts_signature - pl.min_version_time) / 86400)::int8 as days_first_listing_to_contract_signed,
  (date_part('epoch', pl.de_publication_date - pl.min_version_time) / 86400)::int8 as days_listing_to_depublication,
  coalesce(pl.nr_renting::bigint, 0) as nr_renting,
  now()::timestamp as ts_load
from house_franca h
left join house_listing pl
  on pl.id = h.id
left join contract c
  on c.id = pl.contract_id
left join condo cd
  on h.condo_id = cd.id
;