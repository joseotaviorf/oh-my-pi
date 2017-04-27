-- select count(1) from public.potential_listings_temp
  
-- CREATE EXTENSION pg_trgm;

DROP VIEW IF EXISTS vw_fact_supply_potential_listings_temp ;
CREATE VIEW vw_fact_supply_potential_listings_temp as
with first_pub as
(
  SELECT
    p.first_publication as first_publication_date,
    (listing_publication_date = first_publication) as is_first_publication,
    l.*

  FROM

    (SELECT * FROM
      
      (
      SELECT -- add the cap_id to the potential listings table by joining it to the cap table.
        cap.cap_id,
        pl.*
        -- cap.reason
      FROM
        public.potential_listings_temp pl
      left join
        public.contacts_and_prospects cap
        on (cap.lead_id = pl.lead_id)
      WHERE pl.lead_id IS NOT NULL

      UNION

      SELECT -- add the cap_id to the potential listings table by joining it to the cap table.
        cap.cap_id,
        pl.*
        -- cap.reason
      FROM
        public.potential_listings_temp pl
      left join
        public.contacts_and_prospects cap
        on (cap.imovel_id = pl.property_id and pl.lead_id IS NULL)
      WHERE pl.lead_id IS NULL and pl.property_id IS NOT NULL
      ) l





  left join
    vw_dim_property p
    on p.id = l.property_id
--  where l.property_id = 892776892
  WINDOW
    w_prop_id as (partition by l.property_id)
)
, listings as
(
  select
      l.*,
      ------ LISTING DATE COUNTS ------
      (dense_rank()
        over (
          partition by
            date_part('month', first_publication_date),
            date_part('year', first_publication_date)
          order BY
            l.property_id  asc
        )
      + dense_rank()
          over (
            partition by
              date_part('month', first_publication_date),
              date_part('year', first_publication_date)
            order BY
              l.property_id  desc
       )
      -1) as listing_month_distinct_count, -- distinct count inside partition 'year/month'

      (
        dense_rank()
          over (
            partition by
              first_publication_date::date
            order BY
              l.property_id
          )
        +
        dense_rank()
          over (
            partition by
              first_publication_date::date
            order BY
              l.property_id  desc
          )
        -1
      )
      as listing_day_distinct_count,  -- distinct count inside partition 'day'

      count(1) over (
        partition by
          property_id,
          date_part('month', first_publication_date),
          date_part('year', first_publication_date)
      )
      as listing_month_times,  -- how many times they appear over month using listing_date

      count(1) over (partition by first_publication_date::date)
      as listing_day_times,  -- how many times they appear over day using listing_date
      -- count(1) filter (where l.attribution_category='Self-Service')
      count(1) filter (where l.imovel_attribution = 'Self-Service')
      over (partition by first_publication_date::date)
      as self_service_listing_day_times, -- count over day using listing date and filter self-service

    mu.adquirido_em::date as adquirido_em,

      ------ CONTACT DATE COUNTS ------
      (
        dense_rank()
          over (
            partition by
              date_part('month', cast(coalesce(mu.adquirido_em, l.created_date) as date)  ),
              date_part('year', cast(coalesce(mu.adquirido_em, l.created_date) as date)  )
            order BY
              l.property_id
          )
        +
        dense_rank()
          over (
            partition by
              date_part('month', cast(coalesce(mu.adquirido_em, l.created_date) as date)  ),
              date_part('year', cast(coalesce(mu.adquirido_em, l.created_date) as date)  )
            order BY
              l.property_id  desc
          )
        -1
      )
      as contact_month_distinct_count, -- distinct count inside partition 'year/month'

      (
        dense_rank()
          over (
            partition by
              cast(coalesce(mu.adquirido_em, l.created_date) as date)
            order BY
              l.property_id
          )
        +
        dense_rank()
          over (
            partition by
              cast(coalesce(mu.adquirido_em, l.created_date) as date)
            order BY
              l.property_id  desc
          )
        -1
      )
      as contact_day_distinct_count,  -- distinct count inside partition 'day'

      count(1) over (
        partition by
          property_id,
          date_part('month', cast(coalesce(mu.adquirido_em, l.created_date) as date)  ),
          date_part('year', cast(coalesce(mu.adquirido_em, l.created_date) as date)  )
      )
      as contact_month_times,  -- how many times they appear over month using listing_date

      count(1)  over (
        partition by cast(coalesce(mu.adquirido_em, l.created_date) as date)
      )
      as contact_day_times,  -- how many times they appear over day using listing_date

      -- count(1) filter (where l.attribution_category='Self-Service')
      count(1) filter (where l.imovel_attribution = 'Self-Service')
      over (
        partition by cast(coalesce(mu.adquirido_em, l.created_date) as date)
      )
      as self_service_contact_day_times, -- count over day using listing date and filter self-service


      ------ OPPORTUNITY DATE COUNTS ------
      (
        dense_rank()
          over (
            partition by
              date_part('month', l.opportunity_date),
              date_part('year', l.opportunity_date)
            order BY
              l.property_id
          )
        +
        dense_rank()
          over (
            partition by
              date_part('month', l.opportunity_date),
              date_part('year', l.opportunity_date)
            order BY
              l.property_id  desc
          )
        -1
      )
      as opportunity_month_distinct_count, -- distinct count inside partition 'year/month'

      (
        dense_rank()
          over (
            partition by
              opportunity_date::date
            order BY
              l.property_id
          )
        +
        dense_rank()
          over (
            partition by
              opportunity_date::date
            order BY
              l.property_id  desc
          )
        -1
      )
      as opportunity_day_distinct_count,  -- distinct count inside partition 'day'

      count(1) over (
        partition by
          property_id,
          date_part('month', l.opportunity_date),
          date_part('year', l.opportunity_date)
      )
      as opportunity_month_times,  -- how many times they appear over month using listing_date

      count(1)  over (
        partition by opportunity_date::date
      )
      as opportunity_day_times,  -- how many times they appear over day using listing_date

      -- count(1) filter (where l.attribution_category='Self-Service')
      count(1) filter (where l.imovel_attribution != 'Self-Service')
      over (
        partition by opportunity_date::date
      )
      as self_service_opportunity_day_times -- count over day using listing date and filter self-service
  from
    first_pub l
  left join
    (
        select
            mu.usuario_id,
            min(mu.adquirido_em) as adquirido_em
        from
            marketing_attribution mu
        group by
            mu.usuario_id
    ) mu
        on mu.usuario_id = l.owner_id

)
SELECT -- count(1)
  l.cap_id,
  l.id as ods_id,
  ref_date as dt_last_updated,
  created_date as dt_created,
  updated_date as dt_updated,
  attribution_id as sk_attibution,
  attribution_uuid,
  contact_date as dt_contact,
  lead_date as dt_lead,
  prospect_date as dt_prospect,
  first_inside_sales_contact_date as dt_first_inside_sales_contact,
  qualified_date as dt_qualified,
  opportunity_date as dt_opportunity,
  first_publication_date as dt_first_publication,
  listing_publication_date as dt_listing_publication,
  contract_date as dt_contract,

/*  CASE
    WHEN listing_publication_date IS NOT NULL THEN NULL
    WHEN funnel_source = 'Self-Service' THEN 'Unfinished Process'
    WHEN l.reason IS NOT NULL THEN l.reason
    ELSE 'Unknown' -- meaning it's an unpublished lead (from the lead flow) without a reason not to publish
  END as reason, */

  is_first_publication,

  coalesce(to_char(contact_date,'YYYYMMDD')::integer, -1) as sk_contact_date,
  coalesce(to_char(lead_date,'YYYYMMDD')::integer, -1) as sk_lead_date,
  coalesce(to_char(prospect_date,'YYYYMMDD')::integer, -1) as sk_prospect_date,
  coalesce(to_char(first_inside_sales_contact_date,'YYYYMMDD')::integer, -1) as sk_first_inside_sales_contact_date,
  coalesce(to_char(qualified_date,'YYYYMMDD')::integer, -1) as sk_qualified_date,
  coalesce(to_char(opportunity_date,'YYYYMMDD')::integer, -1) as sk_opportunity_date,
  coalesce(to_char(first_publication_date,'YYYYMMDD')::integer, -1) as sk_first_publication_date,
  coalesce(to_char(listing_publication_date,'YYYYMMDD')::integer, -1) as sk_listing_publication_date,
  coalesce(to_char(contract_date,'YYYYMMDD')::integer, -1) as sk_contract_date,

  coalesce(lead_id, -1) as sk_lead,
  coalesce(property_id || '_1', '-1') as sk_property,
  coalesce(l.contract_id, -1) as sk_contract,
  renting_value,
  l.dados_fotografo_id as sk_photographer,
  owner_id as sk_owner,

  rep_id as sk_rep,
  e."Team" as rep_area,
  qt.count_employees_outbound,

  manager_id as sk_manager,
  l.tipo_admin as admin_type,
  imovel_attribution as property_attribution_agent,
  lead_tipo as lead_type,
  -- attribution_type,
  -- attribution_category,

  -- funnel_source,
  contact_to_lead_diff_minutes,
  lead_to_qualified_diff_minutes,
  qualified_to_opportunity_diff_minutes,
  opportunity_to_listing_diff_minutes,
  listing_to_1stcontract_diff_minutes,
  contact_to_listing_diff_minutes,
  contact_to_1stcontract_diff_minutes,


  case when is_first_publication
      then affiliate_listing_value
      else 0
  end as affiliate_listing_value,

  case when is_first_publication
      then affiliate_renting_value
      else 0
  end as affiliate_renting_value,

  case when is_first_publication
      then cac_affiliate -- as cac_affiliate_total,
      else 0
  end as cac_affiliate,


  listing_month_distinct_count, -- distinct count inside partition 'year/month'
  listing_day_distinct_count,  -- distinct count inside partition 'day'
  listing_month_times,  -- how many times they appear over month using listing_date
  listing_day_times,  -- how many times they appear over day using listing_date
  self_service_listing_day_times, -- count over day using listing date and filter self-service
  contact_month_distinct_count, -- distinct count inside partition 'year/month'
  contact_day_distinct_count,  -- distinct count inside partition 'day'
  contact_month_times,  -- how many times they appear over month using listing_date
  contact_day_times,  -- how many times they appear over day using listing_date
  self_service_contact_day_times, -- count over day using listing date and filter self-service
  opportunity_month_distinct_count, -- distinct count inside partition 'year/month'
  opportunity_day_distinct_count,  -- distinct count inside partition 'day'
  opportunity_month_times, -- how many times they appear over month using opportunity_date
  opportunity_day_times,  -- how many times they appear over day using opportunity_date
  self_service_opportunity_day_times,  -- count over day using opportunity_date and filter self-service


  -ph."Value"::decimal(18,4) as photo_month_cost,
  -i."Value"::decimal(18,4) as  inside_sales_month_cost,
  f.cost as facebook_mkt_day_cost,
  f_install.cost as facebook_appinstall_day_cost,
  f.cost + f_install.cost as facebook_total_day_cost,
  g.cost as google_adwords_day_cost,
  f.cost + f_install.cost + g.cost as marketing_day_cost,

  /*
    f_install.cost /
    coalesce(nullif(l.contact_day_distinct_count,0),1) /
    coalesce(nullif(l.self_service_contact_day_times,0),1) as fb_self_service_marketing_cost,
  */

  f_install.cost /
  coalesce(nullif(
          -- count(1) filter (where l.attribution_category='Self-Service')
          count(1) filter (where l.imovel_attribution = 'Self-Service')
          over (
            partition by created_date::date
          )
    ,0),1) as fb_self_service_marketing_cost,

  coalesce(f.cost,0) / coalesce(nullif(l.contact_day_times,0),1) as fb_marketing_cost,

  coalesce(g.cost,0) / coalesce(nullif(l.contact_day_times,0),1) as google_marketing_cost,


  CASE WHEN is_first_publication
  THEN -ph."Value"::decimal(18,4) /
    coalesce(f_get_days_in_month(l.first_publication_date),1) /
    coalesce(nullif(l.listing_day_distinct_count,0),1)
  ELSE
    0
  END as cac_photo,

  CASE WHEN is_first_publication
  THEN -i."Value"::decimal(18,4) /
    coalesce(f_get_days_in_month(l.first_publication_date),1) /
    coalesce(nullif(l.listing_day_distinct_count,0),1)
  ELSE
    0
  END as cac_inside_sales,

  -- cac_affiliate_total::decimal(18,4) / coalesce(count(1) over (partition by sk_property),1) as cac_affiliate,

  (coalesce(f_install.cost,0) / coalesce(nullif(l.contact_day_distinct_count,0),1) / coalesce(nullif(l.self_service_contact_day_times,0),1))
  + (coalesce(f.cost,0) / coalesce(nullif(l.contact_day_times,0),1))
  + (coalesce(g.cost,0) / coalesce(nullif(l.contact_day_times,0),1))::NUMERIC(18,4) as cac_marketing,

  now()::timestamp as load_timestamp

FROM
  listings l

left join
  files.costs_dre i
  on date_part('month', i."Month") = date_part('month', l.first_publication_date)
  and date_part('year', i."Month") = date_part('year', l.first_publication_date)
  and i."Category"='Inside Sales for Sourcing Properties'

left join
  files.costs_dre ph
  on date_part('month', ph."Month") = date_part('month', l.opportunity_date)
  and date_part('year', ph."Month") = date_part('year', l.opportunity_date)
  and ph."Category"='Listing Photos'

left join
  usuario u
    on u.id = l.rep_id

left join
  files.personnel_allocation e
  on similarity(trim(upper(e."Employee")), trim(upper(u.nome))) >= 0.8
  and date_part('month', (to_date(e."Month"::varchar, 'DD/MM/YYYY')))
      = date_part('month', l.first_publication_date)
  and date_part('year', (to_date(e."Month"::varchar, 'DD/MM/YYYY')))
      = date_part('year', l.first_publication_date)

left join
(
  select
    to_date(e."Month"::varchar, 'DD/MM/YYYY') as date_employee_area,
    count(1)::integer as count_employees_outbound
  from
    files.personnel_allocation e
  where lower(e."Team") = 'outbound'
  group by
    to_date(e."Month"::varchar, 'DD/MM/YYYY')
) qt
  on date_part('month', qt.date_employee_area) = date_part('month', l.first_publication_date)
  and date_part('year', qt.date_employee_area) = date_part('year', l.first_publication_date)

left join
  (
    select
      a.date,
      sum(a.spend::decimal(18,4)) as cost
    from facebook_ads_campaigns a
    where
        a.campaign_name like '%install%'
    and a.account_name = 'Supply'
    group by a.date
  ) f_install
  on cast(f_install.date as date) = cast(coalesce(l.adquirido_em, l.created_date) as date)
  -- and l.funnel_source = 'Self-Service'
  and l.imovel_attribution = 'Self-Service'

left join
  (
    select
      a.date,
      sum(a.spend::decimal(18,4)) as cost
    from facebook_ads_campaigns a
    where
        a.campaign_name not like '%install%'
    and a.account_name = 'Supply'
    group by
        a.date
  ) f
  on cast(f.date as date) = cast(coalesce(l.adquirido_em, l.created_date) as date)
  -- and l.funnel_source != 'Self-Service'
  and l.imovel_attribution != 'Self-Service'

left join
  (
    select ad.day, sum(ad.cost::decimal(18,4))/1000000 as cost
    from public.google_ads_campaigns ad
    where ad.campaign_area = 'supply'
    group by ad.day
  ) g
  on cast(g.day as date) = cast(coalesce(l.adquirido_em, l.created_date) as date)

;

/*
 drop table tmp_fact_supply_potential_listings_temp
  ;
 select *
 into tmp_fact_supply_potential_listings_temp
  
 from public.vw_fact_supply_potential_listings_temp
   l
 where  l.sk_property in (892786407, 892786573, 892788018, 892789866)
 -- where  l.sk_property = 892786407
 ;
 select * from tmp_fact_supply_potential_listings_temp
  ;
*/