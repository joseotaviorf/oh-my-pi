with 
opt_out as (
    select
        lbc_aud.id_house,
        max(case when business_context = 'RENT' then from_unixtime(ure.ts_revision / 1000) end) as ts_opt_out_rent,
        max(case when business_context = 'SALE' then from_unixtime(ure.ts_revision / 1000) end) as ts_opt_out_sale
    from datalake_ebdb_clean.listing_business_context_aud lbc_aud
    join datalake_ebdb_clean.user_revision_entity ure on
        ure.id = lbc_aud.rev
    where
        status = 'OPTED_OUT'
        and mod_status = 1
    group by 1
),
revision as (
    select
        lbc_aud.id_house,
        min(case when business_context = 'RENT' then lbc_aud.rev end) as first_rev_rent,
        min(case when business_context = 'SALE' then lbc_aud.rev end) as first_rev_sale
    from datalake_ebdb_clean.listing_business_context_aud as lbc_aud
    group by 1
),
registrant as (
    select
        lbc.id_house,
        ure_rent.id_user as user_listing_registrant_rent,
        ure_sale.id_user as user_listing_registrant_sale
    from datalake_ebdb_clean.listing_business_context lbc
    left join revision as rev on
        rev.id_house = lbc.id_house
    left join datalake_ebdb_clean.user_revision_entity as ure_rent on
        ure_rent.id = rev.first_rev_rent
    left join datalake_ebdb_clean.user_revision_entity as ure_sale on
        ure_sale.id = rev.first_rev_sale
    group by 1, 2, 3
)
select
    lbc.id,
    lbc.id_house,
    lbc.business_context,
    lbc.calculator_price,
    lbc.status,
    lbc.status_reason,
    lbc.status_closing,
    lbc.short_url,
    coalesce(lbc.business_context = 'RENT', false) as is_rent_context,
    coalesce(lbc.business_context = 'SALE', false) as is_sale_context,
    registrant.user_listing_registrant_rent,
    registrant.user_listing_registrant_sale,
    lbc.ts_first_publication as ts_first_listing,
    lbc.ts_last_publication as ts_last_listing,
    opt_out.ts_opt_out_rent,
    opt_out.ts_opt_out_sale,
    lbc.ts_created,
    lbc.ts_updated
from datalake_ebdb_clean.listing_business_context lbc
left join opt_out on
    lbc.id_house = opt_out.id_house
left join registrant on
    lbc.id_house = registrant.id_house
