drop view if exists unit_economics.vw_net_revenue_revenues_mgmt_fee;
---
--- Returns vl_management_fee revenue for each invoice
--- Revenue: Management Fee on rented properties
--- Cash Flow Date: Date of Landlord Payment
---
create or replace view unit_economics.vw_net_revenue_revenues_mgmt_fee as
with filtered_contracts as (
    select distinct
        property_id,
        id,
        init_date,
        package_value,
        coalesce(termination_date, expected_end_date)::date as end_date,
        date_trunc('month', dd.date)::date + interval '6 day' as date_range
    from
        unit_economics.vw_base_contract_costs
    join dim_date dd
        on date_trunc('month', dd.date) between date_trunc('month', init_date)
            and date_trunc('month', coalesce(termination_date, expected_end_date)::date)
    where termination_date is not null
        or expected_end_date is not null
),
base_contract as (
	select
		base.*,
		c.id as contract_id,
		package_value,
		date_trunc('month', c.init_date) as contract_init_date,
		date_trunc('month', c.end_date) as contract_end_date,
		c.date_range
	from
		unit_economics.vw_base_property_costs base
	left join
		filtered_contracts c
		on base.property_id = c.property_id
		and c.end_date between base.min_version_time and base.max_version_time
),
incurred as (
    select
    		row_number() over (partition by sk_property, bc.contract_id order by bc.date_range) as rn,
        sk_property,
        property_id,
        bc.contract_id,
        bc.contract_init_date,
        bc.contract_end_date,
        bc.package_value,
        amount::decimal(14,4) as vl_management_fee,
        greatest(
        	landlord_due_date,
        	due_date,
        	landlord_paid_date --,
        	) as dt_cash_flow,
        bc.date_range
    from
        base_contract bc
    left join
        invoice i
        on bc.contract_id = i.contract_id
            and date_trunc('month', greatest(landlord_due_date, due_date, landlord_paid_date)) = bc.date_range
            and item = 'TaxaAdministracao'
            and landlord_status = 'paid'
            and "from" = 'Proprietario'
            and "to" = 'Contrato'
),
incurred_diff as (
    select
        sk_property,
        property_id,
        case
        	when (rn=1 and vl_management_fee is null)
        		then package_value*0.08
        		else vl_management_fee
        end as vl_management_fee,
        case
        	when (rn=1 and vl_management_fee is null)
        		then contract_init_date + interval '2 month' + interval '6 day'
        		else dt_cash_flow
        end as dt_cash_flow,
        date_range,
        contract_end_date,
        contract_init_date,
        (extract(year from (contract_end_date - contract_init_date)) * 12
                + extract(month from (contract_end_date - contract_init_date))
                + (extract(days from (contract_end_date - contract_init_date)) / 30))::integer as date_diff
    from incurred
),
incurred_plus_dates as (
    select
        sk_property,
        property_id,
        vl_management_fee,
        dt_cash_flow,
        date_range,
        max(dt_cash_flow) over (partition by sk_property) as max_dt_cash_flow
    from incurred_diff
),
value_fill as (
    select distinct
        sk_property,
        property_id,
        vl_management_fee,
        case
            when date_range > max_dt_cash_flow
                then date_range
            else dt_cash_flow
        end as dt_cash_flow,
        max_dt_cash_flow,
        gap_fill(vl_management_fee) over (partition by sk_property order by dt_cash_flow asc) as gf
    from incurred_plus_dates
),
result as (
    select
        sk_property,
        property_id,
        dt_cash_flow,
        case
            when dt_cash_flow > max_dt_cash_flow
                then coalesce(vl_management_fee, gf)
            else vl_management_fee
        end as vl_management_fee,
        dt_cash_flow > max_dt_cash_flow and vl_management_fee is null as flg_expected_management_fee
    from value_fill
)
select
    sk_property,
    property_id,
    vl_management_fee,
    dt_cash_flow,
    flg_expected_management_fee::integer
from result
where vl_management_fee != 0
;
