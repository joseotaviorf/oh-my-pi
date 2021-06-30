with
reviews as (
    select id_reviewed as visit_code,
        cast(max(case when feature.name='painting' then rating_selected[1] else null end) as bigint) as painting,
        cast(max(case when feature.name='costbenefit' then rating_selected[1] else null end) as bigint) as costbenefit,
        cast(max(case when feature.name='listingfidelity' then rating_selected[1] else null end) as bigint) as listingfidelity,
        cast(max(case when feature.name='conservation' then rating_selected[1] else null end) as bigint) as conservation,
        cast(max(case when feature.name='cleaning' then rating_selected[1] else null end) as bigint) as cleaning,
        try(cast(max(case when feature.name='furniture' then rating_selected[1] else null end) as bigint)) as furniture,
        cast(max(case when feature.name='naturallight' then rating_selected[1] else null end) as bigint) as naturallight,
        cast(max(case when feature.name='indoorsilence' then rating_selected[1] else null end) as bigint) as indoorsilence
        
    from datalake_insider_clean_prod.review as review
    inner join datalake_insider_clean_prod.review_feature as feature_rev on review.id = feature_rev.id_review
    inner join datalake_insider_clean_prod.feature as feature on feature_rev.id_feature = feature.id
    where review.status = 'DONE' AND review.type = 'tenant_visit'
    group by id_reviewed
),
reviews_by_house as (
  select
      booking.id_house as id_house,
      round(avg(reviews.painting), 2) as painting,
      round(avg(reviews.costbenefit), 2) as costbenefit,
      round(avg(reviews.listingfidelity), 2) as listingfidelity,
      round(avg(reviews.conservation), 2) as conservation,
      round(avg(reviews.cleaning), 2) as cleaning,
      round(avg(reviews.furniture), 2) as furniture,
      round(avg(reviews.naturallight), 2) as naturallight,
      round(avg(reviews.indoorsilence), 2) as indoorsilence,
      count(*) as number_of_reviews
  from reviews
  join datalake_ebdb_clean_prod.booking as booking on reviews.visit_code = booking.code
  where booking.id_house is not null
  group by 1
),
house_info as (
  select
    dhl.id_house,
    dhl.is_b2b,
    owner.sk_user as owner_id,
    owner.nome as owner_name,
    owner.telefone_principal as owner_phone,
    dhl.house_type,
    dhl.house_address,
    dhl.house_number,
    dhl.house_complement,
    dhl.house_neighborhood,
    dhl.house_city
  from datalake_clean.ods_fact_house_listings fhl
  left join datalake_clean.ods_dim_house_listing dhl on fhl.sk_house_listing = dhl.sk_house_listing
  left join datalake_clean.ods_dim_user owner on fhl.sk_owner = owner.sk_user
  where try(cast(dhl.is_last_version as boolean)) = true
    and coalesce(dhl.ts_publication, '') != ''
  group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
)
select
  hi.*,
  r.painting,
  r.costbenefit,
  r.listingfidelity,
  r.conservation,
  r.cleaning,
  r.furniture,
  r.naturallight,
  r.indoorsilence,
  case
    when r.furniture is not null then round((r.painting + r.costbenefit + r.conservation + r.cleaning + r.furniture + r.naturallight + r.indoorsilence) / 7.0, 2)
    when r.furniture is null then round((r.painting + r.costbenefit + r.conservation + r.cleaning + r.naturallight + r.indoorsilence) / 6.0, 2)
  end as reviews_average,
  r.number_of_reviews
from reviews_by_house r
left join house_info hi on hi.id_house = cast(r.id_house as varchar)
