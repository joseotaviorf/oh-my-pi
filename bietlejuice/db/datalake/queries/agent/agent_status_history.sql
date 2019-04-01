with agent_changes as (
    select
        da.id,
        rev,
        from_unixtime(cast(rv.timestamp as decimal)/1000) as ts_rev,
        revtype,
        ativo,
        coalesce(ativo <> lag(ativo) over (partition by da.id order by rv.timestamp), true) has_changed -- Coalesce true to set rev = 0 as a change
    from datalake_raw.ebdb_dadosagente_aud da
    join datalake_raw.ebdb_usuario_revision_entity rv
        on da.rev = rv.id
)
select
    id as agent_id,
    case
        when ativo = '1' then 'Active'
        else 'Suspended'
        end as status,
    date(ts_rev) as start_date,
    date(lead(ts_rev) over (partition by id order by ts_rev)) as end_date
from agent_changes
where has_changed = true