drop view if exists vw_fact_house_listings;
create or replace view vw_fact_house_listings as
with house_listing_contracts as (
  select
    hl.id as id_house,
    hl.version as house_version,
    c.id as id_contract,
    c.ts_signature as ts_contract_signed,
    c.dt_annulment as dt_contract_annulment,
    lag(c.id) over (partition by hl.id order by hl.version) as id_prev_contract,
    lead(c.ts_signature) over (partition by hl.id order by hl.version) as ts_next_contract_signed
  from house_listing hl
  left join contract c
    on hl.contract_id = c.id
)
select
  ((h.id || '00') || coalesce(hl.version, 1))::bigint as sk_house_listing,
  coalesce(h.usuario_id, -1) as sk_owner,
  coalesce(h.regiao_id, -1) as sk_region,
  coalesce(h.usuario_que_cadastrou_id, -1) as sk_user_registration,
  coalesce(hlc.id_contract, -1) as sk_contract,
  coalesce(cd.id, -1) as sk_condo,
  (date_part('epoch', hlc.ts_contract_signed - hl.min_version_time) / 86400)::integer as days_first_listing_to_contract_signed,
  (date_part('epoch', hl.de_publication_date - hl.min_version_time) / 86400)::integer as days_listing_to_depublication,
  (date_part('epoch', hl.max_version_time - hlc.dt_contract_annulment) / 86400)::integer as days_ended_rental_to_relisting,
  (date_part('epoch', hlc.ts_next_contract_signed - hl.max_version_time) / 86400)::integer as days_relisting_to_re_rental,
  (date_part('epoch', hlc.ts_next_contract_signed - hlc.dt_contract_annulment) / 86400)::integer as days_ended_rental_to_re_rented,
  coalesce(hl.nr_renting::bigint, 0) as nr_renting,
  now()::timestamp as ts_load
from house h
left join house_listing hl
  on hl.id = h.id
left join house_listing_contracts hlc
  on hl.id = hlc.id_house
    and hl.version = hlc.house_version
left join condo cd
  on h.condo_id = cd.id
;
