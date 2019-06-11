with distinct_users as (
    select * from datalake_clean.zendesk_users
    where dt_extracted='{extraction_date}'
),
last_zendesk_user as (
    select id_user, max(ts_updated) as ts_last_updated from distinct_users group by 1
)
select
    cast(du.id_user as bigint) as sk_zendesk_user,
    cast(du.is_active as boolean) as is_active,
    du.url_user,
    du.name,
    du.alias,
    du.email,
    du.phone,
    cast(du.is_shared_phone_number as boolean) as is_shared_phone_number,
    du.time_zone,
    du.locale,
    du.tags,
    du.role,
    cast(du.ts_last_login as timestamp with time zone) as ts_last_login,
    cast(du.ts_created as timestamp with time zone) as ts_created,
    cast(du.ts_created_local as timestamp with time zone) as ts_created_local,
    cast(du.ts_updated as timestamp with time zone) as ts_updated,
    now() as ts_load
from distinct_users du
inner join last_zendesk_user lu
on du.id_user=lu.id_user 
and du.ts_updated=lu.ts_last_updated;