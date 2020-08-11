with cte_first_last_activation as (
    select
        id_smart_price,
        min(case when status = 'ACTIVE' then ts_start_status end) as ts_first_activation,
        max(case when status = 'INACTIVE' then ts_start_status end) as ts_last_deactivation
    from
        datalake_ebdb_smart_price.smart_price_versioning
    group by 1
),
cte_status_is_enabled as(
    select
        smp.id_smart_price,
        smp.id_house,
        smp.id_dynamic_pricing_parameter,
        smp.status,
        dpa.is_enabled,
        dpa.operation_mode,
        row_number() over(partition by smp.id_smart_price order by smp.ts_start_status desc) ranking
    from
        datalake_ebdb_smart_price.smart_price_versioning smp
    join
        datalake_ebdb_clean.dynamic_pricing_house_aud  dpa
            on smp.id_dynamic_pricing = dpa.id
            and smp.rev_dynamic_pricing_house_aud = dpa.rev
),
cte_last_status_is_enabled as (
    select
        id_smart_price,
        id_house,
        id_dynamic_pricing_parameter,
        status,
        is_enabled,
        operation_mode
    from
        cte_status_is_enabled
    where
        ranking = 1
)
select
    fla.id_smart_price as sk_smart_price,
    fla.id_smart_price,
    lsie.is_enabled,
    lsie.operation_mode,
    lsie.status as status,
    dph.status as house_last_status,
    dph.min_rent as house_min_rent,
    dph.initial_rent as house_max_rent,
    dpp.min_rent_percentile,
    dpp.initial_rent_percentile as max_rent_percentile,
    dpp.offers_threshold,
    dpp.days_threshold,
    dpp.visits_days_threshold,
    fla.ts_first_activation,
    fla.ts_last_deactivation,
    now() as ts_load
from
    cte_first_last_activation fla
join
    cte_last_status_is_enabled lsie
        on fla.id_smart_price = lsie.id_smart_price
join
    datalake_ebdb_clean.dynamic_pricing_house dph
        on dph.id_house = lsie.id_house
join
    datalake_ebdb_clean.dynamic_pricing_parameters dpp
        on lsie.id_dynamic_pricing_parameter = dpp.id