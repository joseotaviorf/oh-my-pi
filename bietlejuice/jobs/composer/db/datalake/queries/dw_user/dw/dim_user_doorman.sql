select -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
    id as sk_user_doorman,
    coalesce(id_affiliate_data, -1) as sk_user_affiliate,
    id as id_user_doorman,
    id_doorman_occupation as occupation_id,
    id_place as work_place_id,
    work_address,
    work_street,
    cast(work_house_number as varchar(255)) as work_house_number,
    work_neighborhood as work_neighbourhood,
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
    ts_joined as ts_joined_program,
    now() as ts_load
from
    datalake_ebdb_user.user_doorman
