select
    smp.id_smart_price as sk_smart_price,
    smp.id_house_listing as sk_house_listing,
    cast(date_format(smp.ts_start_status, 'yMMdd') as bigint) as sk_status_started_date,
    cast(date_format(smp.ts_end_status, 'yMMdd') as bigint) as sk_status_ended_date,
    smp.status,
    case
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and ha.mod_rent
            and ure.reason = 'Valor alterado pela feature de preço dinâmico.'
            then 'all falls done'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and lag(ha.mod_rent) over (partition by coalesce(dpa.id_house, ha.id_house) order by coalesce(ure.id, ha.rev))
            and coalesce(ure.reason,'') != 'Valor alterado pela feature de preço dinâmico.'
            then 'price change'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and lag(ha.status) over (partition by coalesce(dpa.id_house, ha.id_house) order by  coalesce(ure.id, ha.rev)) != 'publicado'
            then 'house listing status change'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and ure.reason is null
            and ha.status = 'publicado'
            then 'price change'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and lead(ha.mod_rent) over (partition by coalesce(dpa.id_house , ha.id_house) order by coalesce(ure.id, ha.rev))
            and coalesce(ure.reason,'') != 'Valor alterado pela feature de preço dinâmico.'
            and lead(ha.status) over (partition by coalesce(dpa.id_house, ha.id_house) order by coalesce(ure.id, ha.rev)) = 'publicado'
            then 'price change'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and ure.reason is null
            and lag(dpa.status) over (partition by coalesce(dpa.id_house, ha.id_house) order by coalesce(ure.id, ha.rev)) = 'PENDING'
            then 'never active'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status = true
            then 'dunno'
    end as status_change_reason,
    dpa.is_enabled as is_enabled,
    dpa.operation_mode as operation_mode,
    datediff(ts_end_status, ts_start_status) as days_in_status,
    smp.ts_start_status as ts_status_started,
    smp.ts_end_status as ts_status_ended,
    now() ts_load
from
    datalake_ebdb_smart_price.smart_price_versioning smp
join
    datalake_ebdb_clean.dynamic_pricing_house_aud  dpa
        on smp.id_dynamic_pricing = dpa.id
        and smp.rev_dynamic_pricing_house_aud = dpa.rev
join
    datalake_ebdb_clean.user_revision_entity ure
        on ure.id = dpa.rev
full join
    datalake_ebdb_clean.house_aud ha
        on ha.rev = ure.id
where
    smp.id_house is not null