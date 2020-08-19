--drop view if exists vw_dim_contract;
--create or replace view vw_dim_contract as
with b2b_info as (
  select distinct
    c.id as id_contract,
    -- although these rules are replicated from vw_dim_lead, it would require much work to centralize with ODS right now
    -- TODO: after moving everything to our data lake, we can centralize rules like these ones
    coalesce(coalesce(lo.affiliate_type, l.affiliate_type) = 'B2BPartner'
      or pa_b2b.id is not null
      , false) as is_b2b,
    case
      when coalesce(lo.affiliate_type, l.affiliate_type) = 'B2BPartner'
       then 'online'
      when pa_b2b.id is not null
       then 'prime'
    end as b2b_type,
    case
    -- because a lead can have both 'affiliate_type' = 'B2BPartner' and 'partner_agent.id' not null and we need to
    -- prioritize the first type (online), the following check must be done
      when pa_b2b.id is not null and coalesce(lo.affiliate_type, l.affiliate_type, '') != 'B2BPartner'
        then
          case
            when pj.id is null and h.first_publication is not null
              then 'advanced_negotiation'
            when h.external_id is null or h.external_id ~ '^([a-zA-Z0-9]+-){4}[a-zA-Z0-9]+$'
              then 'standard'
            when h.external_id is not null
              then 'batch'
          end
    end as b2b_prime_type
  from contract c
  join house h
    on c.id_house = h.id
  left join lead_conversion lc
    on lc.id_house = h.id
  left join lead l
    on l.id = lc.id_lead
  left join reprocessed_lead rl
    on rl.id = l.id
  left join lead lo
    on lo.id = rl.id_origin_lead
  left join partner_agent pa_b2b
	  on pa_b2b.user_id = h.usuario_id
  left join house_listing hl
    on h.id = hl.id_house
  left join photo_job pj
    on pj.imovel_id = h.id
    and pj.dt_job_created between hl.ts_listing_version_start and hl.ts_listing_version_end
),
house_b2b_portability as (
    select
        hl.id_house_listing
    from house_listing hl
    join house h
        on h.id = hl.id_house
    join portability por
        on por.id_house = hl.id_house and por.owner_type = 'B2B'
    where por.ts_created between coalesce(hl.ts_listing_version_start, '1900-01-01 00:00:00') and coalesce(hl.ts_listing_version_end, now())
)
select
  c.id as sk_contract,
  c.id as id_contract,
  c.rent,
  c.day_month_due,
  c.guarantee,
  c.type,
  c.status,
  c.dt_start,
  c.ts_signature,
  c.ts_draft_approved,
  c.dt_entrance,
  c.dt_intended_end,
  c.dt_annulment,
  c.condo_payer,
  c.condo_responsible,
  c.iptu_payer,
  c.iptu_responsible,
  c.rental_insurance_installments,
  c.rental_insurance_value,
  c.home_insurance_installments,
  c.home_insurance_value,
  c.first_rental_commission,
  c.monthly_administration_fee,
  c.condo,
  c.iptu,
  c.signature_type,
  c.closing_status,
  c.ts_created,
  c.ts_updated,
  c.ts_canceled,
  c.cancellation_reason,
  (hp.id_house_listing is not null) or bi.is_b2b as is_b2b,
  bi.b2b_type,
  case
      when hp.id_house_listing is not null then 'portability'
      else bi.b2b_prime_type
  end as b2b_prime_type,
  c.ts_analyst_annulment_input,
  c.contract_version as version,
  c.is_ongoing_contract,
  now() as ts_load
from contract c
left join b2b_info bi
  on c.id = bi.id_contract
left join house_listing hl
	on hl.id_house = c.id_house
	and c.ts_created between coalesce(hl.ts_listing_version_start, '1900-01-01') and coalesce(hl.ts_listing_version_end, now())
left join house_b2b_portability hp
    on hp.id_house_listing = hl.id_house_listing
;