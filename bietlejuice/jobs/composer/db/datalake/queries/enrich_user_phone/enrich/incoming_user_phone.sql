with
incoming_phone as (
    select
        id_call,
        incoming_phone_number,
        year,
        month,
        day
    from datalake_bigfone.incoming_phone
    where year={year} and month={month} and day={day}
),
ebdb_main_phone as (
    select
        max(id) as id,
        replace(main_phone,'+55') as main_phone
    from datalake_ebdb_clean.user
    where main_phone is not null
    group by 2
),
ebdb_secondary_phone as (
    select
        max(id) as id,
        replace(secondary_phone,'+55') as secondary_phone
    from datalake_ebdb_clean.user
    where secondary_phone is not null
    group by 2
),
ebdb_business_phone as (
    select
        max(id) as id,
        replace(business_phone,'+55') as business_phone
    from datalake_ebdb_clean.user
    where business_phone is not null
    group by 2
),
ebdb_old_phone as (
    select
        max(id) as id,
        replace(old_phone,'+55') as old_phone
    from datalake_ebdb_clean.user
    where old_phone is not null
    group by 2
)
select
    max(coalesce(mp.id, sp.id, bp.id, op.id)) as id_user,
    incoming.id_call,
    incoming.year,
    incoming.month,
    incoming.day
from incoming_phone incoming
left join ebdb_main_phone mp
    on incoming.incoming_phone_number=mp.main_phone
left join ebdb_secondary_phone sp
    on incoming.incoming_phone_number=sp.secondary_phone
left join ebdb_business_phone bp
    on incoming.incoming_phone_number=bp.business_phone
left join ebdb_old_phone op
    on incoming.incoming_phone_number=op.old_phone
where coalesce(mp.id, sp.id, bp.id, op.id) is not null
group by 2,3,4,5