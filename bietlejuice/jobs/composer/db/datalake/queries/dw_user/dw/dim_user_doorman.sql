select
    id as sk_user_doorman,
    coalesce(id_affiliate_data, -1) as sk_user_affiliate,
    id as id_user_doorman,
    id_doorman_occupation,
    id_place as id_work_place,
    work_address,
    work_street,
    work_house_number,
    work_neighborhood,
    work_city,
    work_state,
    cast(cast(lat as integer) as decimal) as work_lat,
    cast(cast(lng as integer) as decimal) as work_lng,
    recruiter,
    subscription_source,
    occupation_name,
    is_active,
    ts_created,
    ts_updated,
    ts_joined,
    now() as ts_load
from
    datalake_ebdb_user.user_doorman
