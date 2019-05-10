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
  coalesce(nullif(nullif(h.usuario_id, pa_b2b_online.user_id), pa_b2b_prime.user_id), -1) as sk_owner,
  coalesce(h.regiao_id, -1) as sk_region,
  coalesce(h.usuario_que_cadastrou_id, -1) as sk_user_registration,
  coalesce(hlc.id_contract, -1) as sk_contract,
  coalesce(cd.id, -1) as sk_condo,
  coalesce(pa_b2b_online.user_id, pa_b2b_prime.user_id, -1) as sk_user_partner_agent,
  coalesce(pa_b2b_online.partner_id, pa_b2b_prime.partner_id, -1) as sk_partner,
  coalesce(to_char(st.stranded_date,'YYYYMMDD')::bigint,-1) as sk_stranded_date,
  date_part('day', hlc.ts_contract_signed - hl.min_version_time)::integer as days_listing_to_contract_signed,
  date_part('day', hl.de_publication_date - hl.min_version_time)::integer as days_listing_to_depublication,
  date_part('day', hl.max_version_time - hlc.dt_contract_annulment)::integer as days_ended_rental_to_relisting,
  date_part('day', hlc.ts_next_contract_signed - hl.max_version_time)::integer as days_relisting_to_re_rental,
  date_part('day', hlc.ts_next_contract_signed - hlc.dt_contract_annulment)::integer as days_ended_rental_to_re_rented,
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
left join partner_agent pa_b2b_prime
  on h.usuario_id = pa_b2b_prime.user_id
left join lead_conversion lc
  on lc.id_house = h.id
left join lead l
  on l.id = lc.id_lead
left join user_affiliate ua
  on l.usuario_que_indicou_id = ua.id
    and ua.affiliateType = 'B2BPartner'
left join usuario u_b2b_online
   on u_b2b_online.dados_afiliado_id = ua.id
left join partner_agent pa_b2b_online
  on pa_b2b_online.user_id = u_b2b_online.id
left join vw_stranded_house_listings st
  on ((hl.id || '00') || coalesce(hl.version, 1))::bigint = st.sk_house
;
