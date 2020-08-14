select
    dad.id,
    ad.id as id_affiliate_data,
    dad.id_doorman_occupation,
    dad.id_place,
    dad.work_address,
    dad.work_street,
    dad.work_house_number,
    dad.work_neighborhood,
    dad.work_city,
    dad.work_state,
    dad.lat,
    dad.lng,
    dad.recrutier as recruiter,
    dad.subscription_source,
    dao.name as occupation_name,
    ad.id_doorman_affiliate_data is not null and ad.affiliate_type = 'Doorman' and dad.ts_joined is not null as is_active,
    dad.ts_joined,
    dad.ts_created,
    dad.ts_updated
from datalake_ebdb_clean.doorman_affiliate_data dad
left join datalake_ebdb_clean.affiliate_data ad
    on ad.id_doorman_affiliate_data = dad.id
left join datalake_ebdb_clean.user u
    on u.id_affiliates = ad.id
left join datalake_ebdb_clean.doorman_affiliate_occupation dao
    on dad.id_doorman_occupation = dao.id
