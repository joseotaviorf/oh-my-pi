with base as(
select
    smp.id_smart_price as sk_smart_price,
    smp.id_house_listing as sk_house_listing,
    ure.id_user AS sk_user,
    cast(date_format(smp.ts_start_status, 'yMMdd') as bigint) as sk_status_started_date,
    cast(date_format(smp.ts_end_status, 'yMMdd') as bigint) as sk_status_ended_date,
    smp.status,
    case
        when dpa.status = 'INACTIVE'
            and dpa.mod_is_enabled = true
            and dpa.is_enabled = false
            and dpa.operation_mode = 'AUTO'
            and ts_start_status >= date '2020-05-11'
            then 'Owner deactivated SmP operating in auto mode'
        when dpa.status = 'INACTIVE'
            and dpa.mod_is_enabled = true
            and dpa.is_enabled = false
            and dpa.operation_mode != 'AUTO'
            and ts_start_status >= date '2020-05-11'
            then 'Owner deactivated SmP operating in manual mode'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and ha.mod_rent
            and ure.reason = 'Valor alterado pela feature de preço dinâmico.'
            and ha.rent = dpa.min_rent
            then 'Smart price reached min rent'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and lag(ha.status) over (partition by coalesce(dpa.id_house, ha.id_house) order by coalesce(ure.id, ha.rev)) = 'despublicado'
            then 'The house was unpublished'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and lag(ha.status) over (partition by coalesce(dpa.id_house, ha.id_house) order by coalesce(ure.id, ha.rev)) = 'edicao'
            then 'The house is in editing'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and dpa.is_enabled = False
            and lag(ha.mod_rent) over (partition by coalesce(dpa.id_house, ha.id_house) order by coalesce(ure.id, ha.rev))
            and coalesce(ure.reason,'') != 'Valor alterado pela feature de preço dinâmico.'
            then 'Owner changed published price'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and lag(ha.status) over (partition by coalesce(dpa.id_house, ha.id_house) order by  coalesce(ure.id, ha.rev)) != 'publicado'
            then 'house listing status change'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and lead(ha.mod_rent) over (partition by coalesce(dpa.id_house , ha.id_house) order by coalesce(ure.id, ha.rev))
            and coalesce(ure.reason,'') != 'Valor alterado pela feature de preço dinâmico.'
            and lead(ha.status) over (partition by coalesce(dpa.id_house, ha.id_house) order by coalesce(ure.id, ha.rev)) = 'publicado'
            then 'Owner changed published price'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and ure.reason is null
            and lag(dpa.status) over (partition by coalesce(dpa.id_house, ha.id_house) order by coalesce(ure.id, ha.rev)) = 'PENDING'
            and dpa.is_enabled = false
            then 'The smart price was never been activated'
       when dpa.status = 'INACTIVE'
            and dpa.mod_status
            and ure.reason is null
            and lag(dpa.status) over (partition by coalesce(dpa.id_house, ha.id_house) order by coalesce(ure.id, ha.rev)) = 'PAUSED'
            and dpa.is_enabled = false
            then 'The house was reserved'
        when dpa.status = 'INACTIVE'
            and dpa.mod_status = true
            then 'dunno'
    end as status_change_reason,
    dpa.is_enabled as is_enabled,
    dpa.operation_mode as operation_mode,
    datediff(ts_end_status, ts_start_status) as days_in_status,
    smp.ts_start_status as ts_status_started,
    smp.ts_end_status as ts_status_ended
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
)
select
	sk_smart_price,
	sk_house_listing,
	sk_user,
	sk_status_started_date,
	sk_status_ended_date,
	status,
	status_change_reason,
	operation_mode,
	is_enabled,
	days_in_status,
	ts_status_started,
	ts_status_ended,
	now() as ts_load
from
	base
where
	sk_house_listing is not null
