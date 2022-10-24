select
    ad.id,
    ad.id_city,
    ad.creci_number,
    ad.profile,
    ad.is_active,
    max(nullif(ad.creci_number, '') is not null) as is_realstate_agent,
    max(u.is_photographer) as is_photographer,
    max(coalesce(adbc.business_context = 'SALE', false)) as is_sale_agent,
    -- non existent agents on businessContextsServed table are assumed as RENT
    max(coalesce(adbc.business_context, 'RENT') = 'RENT') as is_rent_agent
from datalake_ebdb_clean.agent_data as ad
left join datalake_ebdb_clean.agent_data_business_contexts_served adbc
    on adbc.id_agent_data = ad.id
left join datalake_ebdb_user.user u
    on u.id_agent = ad.id
group by 1, 2, 3, 4, 5