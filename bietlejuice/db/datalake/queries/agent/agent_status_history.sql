with agent_changes as (
    select
        da.id,
        rev,
        from_unixtime(cast(rv.ts_revision as decimal)/1000) as ts_rev,
        rev_type,
        is_active as ativo,
        coalesce(is_active <> lag(is_active) over (partition by da.id order by rv.ts_revision), true) has_changed -- Coalesce true to set rev = 0 as a change
    from datalake_ebdb_clean_prod.agent_data_aud da
    join datalake_ebdb_clean_prod.user_revision_entity rv
        on da.rev = rv.id
)
select
    id as agent_id,
    case
        when ativo then 'Active'
        else 'Suspended'
        end as status,
    date(ts_rev) as start_date,
    date(lead(ts_rev) over (partition by id order by ts_rev)) as end_date
from agent_changes
where has_changed = true
