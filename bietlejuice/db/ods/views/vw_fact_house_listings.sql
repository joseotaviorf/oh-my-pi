--drop view if exists vw_fact_house_listings;
--create or replace view vw_fact_house_listings as
with house_listing_contracts as (
  with latest_contract as (
    select
    	hl.id_house_listing,
    	max(c.id) as id_contract
   from house_listing hl
   join contract c
    on hl.id_house = c.id_house
    	and c.ts_created between coalesce(hl.ts_listing_version_start, '2000-01-01 00:00:00') and coalesce(hl.ts_listing_version_end, current_date)
    	  and c.status in ('Ativo', 'Finalizado')
   group by 1
  )
  select
    hl.id_house_listing,
    hl.version as house_version,
    c.id as id_contract,
    c.ts_signature as ts_contract_signed,
    c.dt_annulment as dt_contract_annulment,
    lag(c.id,1) over (partition by hl.id_house order by hl.version) as id_prev_contract,
    lead(c.ts_signature,1) over (partition by hl.id_house order by hl.version) as ts_next_contract_signed,
    count(c.id) over (partition by c.id_house) as nr_renting
  from house_listing hl
  left join latest_contract lc
  	on hl.id_house_listing = lc.id_house_listing
  left join contract c
  	on c.id = lc.id_contract
),
lbc as (
    select id_house,
	   max((business_context = 'SALE')::integer)::boolean as is_for_sale,
	   max((business_context = 'RENT')::integer)::boolean as is_for_rent
    from
       listing_business_context
    group by 1
),
autonomous_agent_info as (
SELECT DISTINCT
	h.id as id_house,
	pa.user_id as sk_autonomous_agent
FROM
	partner_agent pa
JOIN partner dp ON
	pa.partner_id = dp.id
JOIN house h ON
	pa.user_id = h.usuario_que_cadastrou_id
LEFT JOIN listing_business_context lbc ON
	lbc.id_house = h.id
WHERE
	lbc.business_context <> 'SALE'
	AND dp.type = 'AUTONOMOUS_AGENT'
	AND dp.id <> '257' -- Test User
	AND h.data_criacao >= pa.ts_created --This rule might change when we start to considering migration
	AND h.external_id IS NOT NULL --This rule might change when we start to considering migration
)
select
  hl.id_house_listing as sk_house_listing,
  coalesce(nullif(nullif(h.usuario_id, pa_b2b_online.user_id), pa_b2b_prime.user_id), -1) as sk_owner,
  coalesce(h.regiao_id, -1) as sk_region,
  coalesce(h.usuario_que_cadastrou_id, -1) as sk_user_registration,
  coalesce(hlc.id_contract, -1) as sk_contract,
  coalesce(cd.id, -1) as sk_condo,
  coalesce(pa_b2b_online.user_id, pa_b2b_prime.user_id, -1) as sk_user_partner_agent,
  coalesce(pa_b2b_online.partner_id, pa_b2b_prime.partner_id, -1) as sk_partner,
  coalesce(aa_info.sk_autonomous_agent,-1) as sk_autonomous_agent,
  coalesce(to_char(st.stranded_date,'YYYYMMDD')::bigint,-1) as sk_stranded_date,
  date_part('day', hlc.ts_contract_signed - hl.ts_listing_version_start)::integer as days_listing_to_contract_signed,
  date_part('day', hl.ts_last_de_publication - hl.ts_listing_version_start)::integer as days_listing_to_depublication,
  date_part('day', hl.ts_listing_version_end - hlc.dt_contract_annulment)::integer as days_ended_rental_to_relisting,
  date_part('day', hlc.ts_next_contract_signed - hl.ts_listing_version_end)::integer as days_relisting_to_re_rental,
  date_part('day', hlc.ts_next_contract_signed - hlc.dt_contract_annulment)::integer as days_ended_rental_to_re_rented,
  coalesce(hlc.nr_renting::smallint, 0) as nr_renting,
  now()::timestamp as ts_load
from house h
left join lbc
  on lbc.id_house = h.id
join house_listing hl
  on hl.id_house = h.id
left join house_listing_contracts hlc
  on hl.id_house_listing = hlc.id_house_listing
left join condo cd
  on h.condo_id = cd.id
left join partner_agent pa_b2b_prime
  on h.usuario_id = pa_b2b_prime.user_id
left join lead_conversion lc
  on lc.id_house = h.id
left join lead l
  on l.id = lc.id_lead
    and l.affiliate_type = 'B2BPartner'
left join partner_agent pa_b2b_online
  on pa_b2b_online.user_id = l.usuario_que_indicou_id
-- selecting from a view instead of a CTE just to make code clearer
left join vw_stranded_house_listings st
  on hl.id_house_listing = st.sk_house_listing
left join autonomous_agent_info aa_info
  on aa_info.id_house = h.id
where
  lbc.id_house is null
  or lbc.is_for_rent
;
