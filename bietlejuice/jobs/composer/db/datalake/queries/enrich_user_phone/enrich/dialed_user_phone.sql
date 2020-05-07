with
dialed_phone as (
    select
        id_call,
        phone,
        year,
        month,
        day
    from datalake_bigfone.dialed_phone
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
    dial.id_call,
    dial.year,
    dial.month,
    dial.day
from dialed_phone dial
left join ebdb_main_phone mp
    on dial.phone=mp.main_phone
left join ebdb_secondary_phone sp
    on dial.phone=sp.secondary_phone
left join ebdb_business_phone bp
    on dial.phone=bp.business_phone
left join ebdb_old_phone op
    on dial.phone=op.old_phone
where coalesce(mp.id, sp.id, bp.id, op.id) is not null
group by 2,3,4,5