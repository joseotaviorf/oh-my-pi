drop view if exists unit_economics.vw_fact_property_economics;
---
--- Returns the final view for Unit Economics
--- Cost: All costs grouped by versioned property / cash flow date
--- Cash Flow Date: Date of Payment
--- Placeholders with random int will be kept while developing the remainder values
---

create or replace view unit_economics.vw_fact_property_economics as
with unit_economics as (
    select
        sk_property,
        property_id,
        sk_cash_flow_date,
        dt_cash_flow,
        -sum(vl_owner_campaigns) as vl_owner_campaigns,
        -sum(vl_affiliate_campaigns) as vl_affiliate_campaigns,
        sum(vl_inside_sales) as vl_inside_sales,
        sum(vl_photos) as vl_photos,
        -sum(vl_affiliate_bonus) as vl_affiliate_bonus,
        -sum(vl_lockbox) as vl_lockbox,
        -sum(vl_tenant_campaigns) as vl_tenant_campaigns,
        sum(vl_cs_pre_sale) as vl_cs_pre_sale,
        sum(vl_field_ops) as vl_field_ops,
        sum(vl_bo_pre_sale) as vl_bo_pre_sale,
        sum(vl_agent_hours) as vl_agent_hours,
        -sum(vl_st_pis_cofins) as vl_st_pis_cofins,
        -sum(vl_st_iss) as vl_st_iss,
        -sum(vl_affiliate_commission) as vl_affiliate_commission,
        -sum(vl_agent_commission) as vl_agent_commission,
        sum(vl_delay_fine) as vl_delay_fine,
        0 as vl_termination_fine,
        sum(vl_brokerage_fee) as vl_brokerage_fee,
        sum(vl_management_fee) as vl_management_fee,
        sum(vl_cs_post_sale) as vl_cs_post_sale,
        sum(vl_collection) as vl_collection,
        sum(vl_bo_onboarding) as vl_bo_onboarding,
        sum(vl_bo_ongoing) as vl_bo_ongoing,
        sum(vl_bo_offboarding) as vl_bo_offboarding,
        sum(vl_inspections) as vl_inspections,
        -sum(vl_insurance_fee) as vl_insurance_fee,
        sum(flg_expected_bo_offboarding) as flg_expected_bo_offboarding,
        sum(flg_expected_bo_onboarding) as flg_expected_bo_onboarding,
        sum(flg_expected_bo_ongoing) as flg_expected_bo_ongoing,
        sum(flg_expected_collection) as flg_expected_collection,
        sum(flg_expected_cs_post_sale) as flg_expected_cs_post_sale,
        sum(flg_expected_inspection) as flg_expected_inspection,
        sum(flg_expected_insurance_fee) as flg_expected_insurance_fee,
        sum(flg_expected_management_fee) as flg_expected_management_fee,
        sum(flg_expected_brokerage_fee) as flg_expected_brokerage_fee,
        sum(flg_expected_affiliate_commission) as flg_expected_affiliate_commission,
        sum(flg_expected_agent_commission) as flg_expected_agent_commission,
        sum(flg_expected_sales_tax_iss) as flg_expected_sales_tax_iss,
        sum(flg_expected_sales_tax_pis_cofins) as flg_expected_sales_tax_pis_cofins,
        sum(flg_expected_delay_fine) as flg_expected_delay_fine
    from
    (
        select
            sk_property,
            property_id,
            coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            dt_cash_flow,
            0 as vl_owner_campaigns,
            0 as vl_affiliate_campaigns,
            0 as vl_inside_sales,
            0 as vl_photos,
            0 as vl_affiliate_bonus,
            vl_lockbox as vl_lockbox,
            vl_tenant_campaigns,
            vl_cs_pre_sale as vl_cs_pre_sale,
            vl_field_ops as vl_field_ops,
            vl_bo_pre_sale as vl_bo_pre_sale,
            vl_agent_hours as vl_agent_hours,
            0 as vl_st_pis_cofins,
            0 as vl_st_iss,
            0 as vl_affiliate_commission,
            0 as vl_agent_commission,
            0 as vl_delay_fine,
            0 as vl_termination_fine,
            0 as vl_brokerage_fee,
            0 as vl_management_fee,
            0 as vl_cs_post_sale,
            0 as vl_collection,
            0 as vl_bo_onboarding,
            0 as vl_bo_ongoing,
            0 as vl_bo_offboarding,
            0 as vl_inspections,
            0 as vl_insurance_fee,
            0 as flg_expected_bo_offboarding,
            0 as flg_expected_bo_onboarding,
            0 as flg_expected_bo_ongoing,
            0 as flg_expected_collection,
            0 as flg_expected_cs_post_sale,
            0 as flg_expected_inspection,
            0 as flg_expected_insurance_fee,
            0 as flg_expected_management_fee,
            0 as flg_expected_brokerage_fee,
            0 as flg_expected_affiliate_commission,
            0 as flg_expected_agent_commission,
            0 as flg_expected_sales_tax_iss,
            0 as flg_expected_sales_tax_pis_cofins,
            0 as flg_expected_delay_fine
        from
            unit_economics.vw_liquidity_costs
        union all
        select
            sk_property,
            property_id,
            coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            dt_cash_flow,
            vl_owner_campaigns,
            vl_affiliate_campaigns,
            vl_inside_sales as vl_inside_sales,
            vl_photos as vl_photos,
            vl_affiliate_bonus,
            0 as vl_lockbox,
            0 as vl_tenant_campaigns,
            0 as vl_cs_pre_sale,
            0 as vl_field_ops,
            0 as vl_bo_pre_sale,
            0 as vl_agent_hours,
            0 as vl_st_pis_cofins,
            0 as vl_st_iss,
            0 as vl_affiliate_commission,
            0 as vl_agent_commission,
            0 as vl_delay_fine,
            0 as vl_termination_fine,
            0 as vl_brokerage_fee,
            0 as vl_management_fee,
            0 as vl_cs_post_sale,
            0 as vl_collection,
            0 as vl_bo_onboarding,
            0 as vl_bo_ongoing,
            0 as vl_bo_offboarding,
            0 as vl_inspections,
            0 as vl_insurance_fee,
            0 as flg_expected_bo_offboarding,
            0 as flg_expected_bo_onboarding,
            0 as flg_expected_bo_ongoing,
            0 as flg_expected_collection,
            0 as flg_expected_cs_post_sale,
            0 as flg_expected_inspection,
            0 as flg_expected_insurance_fee,
            0 as flg_expected_management_fee,
            0 as flg_expected_brokerage_fee,
            0 as flg_expected_affiliate_commission,
            0 as flg_expected_agent_commission,
            0 as flg_expected_sales_tax_iss,
            0 as flg_expected_sales_tax_pis_cofins,
            0 as flg_expected_delay_fine
        from
            unit_economics.vw_supply_costs
        union all
        select
            sk_property,
            property_id,
            coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            dt_cash_flow,
            0 as vl_owner_campaigns,
            0 as vl_affiliate_campaigns,
            0 as vl_inside_sales,
            0 as vl_photos,
            0 as vl_affiliate_bonus,
            0 as vl_lockbox,
            0 as vl_tenant_campaigns,
            0 as vl_cs_pre_sale,
            0 as vl_field_ops,
            0 as vl_bo_pre_sale,
            0 as vl_agent_hours,
            vl_st_pis_cofins,
            0 as vl_st_iss,
            0 as vl_affiliate_commission,
            0 as vl_agent_commission,
            0 as vl_delay_fine,
            0 as vl_termination_fine,
            0 as vl_brokerage_fee,
            0 as vl_management_fee,
            vl_cs_post_sale as vl_cs_post_sale,
            vl_collection as vl_collection,
            vl_bo_onboarding as vl_bo_onboarding,
            vl_bo_ongoing as vl_bo_ongoing,
            vl_bo_offboarding as vl_bo_offboarding,
            vl_inspections as vl_inspections,
            vl_insurance_fee as vl_insurance_fee,
            flg_expected_bo_offboarding as flg_expected_bo_offboarding,
            flg_expected_bo_onboarding as flg_expected_bo_onboarding,
            flg_expected_bo_ongoing as flg_expected_bo_ongoing,
            flg_expected_collection as flg_expected_collection,
            flg_expected_cs_post_sale as flg_expected_cs_post_sale,
            flg_expected_inspection as flg_expected_inspection,
            flg_expected_insurance_fee as flg_expected_insurance_fee,
            0 as flg_expected_management_fee,
            0 as flg_expected_brokerage_fee,
            0 as flg_expected_affiliate_commission,
            0 as flg_expected_agent_commission,
            0 as flg_expected_sales_tax_iss,
            flg_expected_sales_tax_pis_cofins,
            0 as flg_expected_delay_fine
        from
            unit_economics.vw_mgmt_costs
        union all
        select
            sk_property,
            property_id,
            coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
            dt_cash_flow,
            0 as vl_owner_campaigns,
            0 as vl_affiliate_campaigns,
            0 as vl_inside_sales,
            0 as vl_photos,
            0 as vl_affiliate_bonus,
            0 as vl_lockbox,
            0 as vl_tenant_campaigns,
            0 as vl_cs_pre_sale,
            0 as vl_field_ops,
            0 as vl_bo_pre_sale,
            0 as vl_agent_hours,
            vl_st_pis_cofins as vl_st_pis_cofins,
            vl_st_iss as vl_st_iss,
            vl_affiliate_commission as vl_affiliate_commission,
            vl_agent_commission as vl_agent_commission,
            vl_delay_fine as vl_delay_fine,
            0 as vl_termination_fine,
            vl_brokerage_fee as vl_brokerage_fee,
            vl_management_fee as vl_management_fee,
            0 as vl_cs_post_sale,
            0 as vl_collection,
            0 as vl_bo_onboarding,
            0 as vl_bo_ongoing,
            0 as vl_bo_offboarding,
            0 as vl_inspections,
            0 as vl_insurance_fee,
            0 as flg_expected_bo_offboarding,
            0 as flg_expected_bo_onboarding,
            0 as flg_expected_bo_ongoing,
            0 as flg_expected_collection,
            0 as flg_expected_cs_post_sale,
            0 as flg_expected_inspection,
            0 as flg_expected_insurance_fee,
            flg_expected_management_fee as flg_expected_management_fee,
            flg_expected_brokerage_fee as flg_expected_brokerage_fee,
            flg_expected_affiliate_commission as flg_expected_affiliate_commission,
            flg_expected_agent_commission as flg_expected_agent_commission,
            flg_expected_sales_tax_iss as flg_expected_sales_tax_iss,
            flg_expected_sales_tax_pis_cofins as flg_expected_sales_tax_pis_cofins,
            flg_expected_delay_fine as flg_expected_delay_fine
        from
            unit_economics.vw_net_revenue_costs
    ) tbl
    group by sk_property, property_id, sk_cash_flow_date, dt_cash_flow
),
-- change to fact_liquidity when versioning is fixed
contracts as (
	select
		id as sk_contract,
		property_id,
		signature_date as start_date,
		case
			when coalesce(termination_date, expected_end_date)::date > now()::date
				then now()::date
			else coalesce(termination_date, expected_end_date)::date
		end as end_date
	from unit_economics.vw_base_contract_costs
	where signature_date is not null
	  and (termination_date is not null or expected_end_date is not null)
),
final_version as (
  select
    ue.sk_property,
    ue.property_id,
    coalesce(c.sk_contract, -1) as sk_contract,
    ue.sk_cash_flow_date,
    ue.vl_owner_campaigns,
    ue.vl_affiliate_campaigns,
    ue.vl_inside_sales,
    ue.vl_photos,
    ue.vl_affiliate_bonus,
    ue.vl_lockbox,
    ue.vl_tenant_campaigns,
    ue.vl_cs_pre_sale,
    ue.vl_field_ops,
    ue.vl_bo_pre_sale,
    ue.vl_agent_hours,
    ue.vl_st_pis_cofins,
    ue.flg_expected_sales_tax_pis_cofins,
    ue.vl_st_iss,
    ue.flg_expected_sales_tax_iss,
    ue.vl_affiliate_commission,
    ue.flg_expected_affiliate_commission,
    ue.vl_agent_commission,
    ue.flg_expected_agent_commission,
    ue.vl_delay_fine,
    ue.flg_expected_delay_fine,
    ue.vl_termination_fine,
    ue.vl_brokerage_fee,
    ue.flg_expected_brokerage_fee,
    ue.vl_management_fee,
    ue.flg_expected_management_fee,
    ue.vl_cs_post_sale,
    ue.flg_expected_cs_post_sale,
    ue.vl_collection,
    ue.flg_expected_collection,
    ue.vl_bo_onboarding,
    ue.flg_expected_bo_onboarding,
    ue.vl_bo_ongoing,
    ue.flg_expected_bo_ongoing,
    ue.vl_bo_offboarding,
    ue.flg_expected_bo_offboarding,
    ue.vl_inspections,
    ue.flg_expected_inspection,
    ue.vl_insurance_fee,
    ue.flg_expected_insurance_fee
  from unit_economics ue
  left join contracts c
    on ue.property_id = c.property_id
       and ue.dt_cash_flow between c.start_date and c.end_date
)
,
first_pubs as (
    select
        i.id as property_id,
        COALESCE(h.dt_first_publication, i.first_publication) AS first_publication
    from
        imovel i
    left join
        (
          select
              a.id,
            min(a.status_time) AS dt_first_publication
          from imovel_status_history a
          where a.published = 1
          group by a.id
        ) h
        ON h.id = i.id
),
before_loss_factor as (
    select
        fv.*,
		(substring(fv.sk_cash_flow_date::varchar, 1, 4)
			|| '-' || substring(fv.sk_cash_flow_date::varchar, 5, 2)
			|| '-' || substring(fv.sk_cash_flow_date::varchar, 7, 2))::date as sk_date
    from final_version fv
    left join first_pubs dp
      on fv.property_id = dp.property_id
    where fv.sk_cash_flow_date != -1
          and coalesce(replace(dp.first_publication::date::varchar, '-', '')::integer, -1) <= fv.sk_cash_flow_date
),
fact_contract as (
	select 
		blf.*,
		(date_part('year', blf.sk_date) - date_part('year', c."dataAssinado"::date)) * 12 +
	              (date_part('month', blf.sk_date) - date_part('month', c."dataAssinado"::date)) as months_diff
	from before_loss_factor blf
	left join contract c
		on blf.sk_contract = c.id
)
select 
	fc.sk_property,
	fc.property_id,
	fc.sk_contract,
	fc.sk_cash_flow_date,
	fc.vl_owner_campaigns,
    fc.vl_affiliate_campaigns,
    fc.vl_inside_sales,
    fc.vl_photos,
    fc.vl_affiliate_bonus,
    fc.vl_lockbox,
    fc.vl_tenant_campaigns,
    fc.vl_cs_pre_sale,
    fc.vl_field_ops,
    fc.vl_bo_pre_sale,
    fc.vl_agent_hours,
	coalesce(fc.vl_st_pis_cofins * (1 - sum(cf.loss_factor) 
			    filter (where fc.flg_expected_sales_tax_pis_cofins = 1) 
					over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_st_pis_cofins) as vl_st_pis_cofins,
    fc.flg_expected_sales_tax_pis_cofins,
	coalesce(fc.vl_st_iss * (1 - sum(cf.loss_factor) 
				filter (where fc.flg_expected_sales_tax_iss = 1) 
					over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_st_iss) as vl_st_iss,
    fc.flg_expected_sales_tax_iss,
	coalesce(fc.vl_bo_ongoing * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_affiliate_commission = 1) 
				over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_affiliate_commission) as vl_affiliate_commission,
    fc.flg_expected_affiliate_commission,
	coalesce(fc.vl_agent_commission * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_agent_commission = 1) 
				over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_agent_commission) as vl_agent_commission,
    fc.flg_expected_agent_commission,
	coalesce(fc.vl_delay_fine * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_delay_fine = 1) 
				over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_delay_fine) as vl_delay_fine,
    fc.flg_expected_delay_fine,
    fc.vl_termination_fine,
	coalesce(fc.vl_brokerage_fee * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_brokerage_fee = 1) 
				over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_brokerage_fee) as vl_brokerage_fee,
    fc.flg_expected_brokerage_fee,
	coalesce(fc.vl_management_fee * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_management_fee = 1) 
				over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_management_fee) as vl_management_fee,
    fc.flg_expected_management_fee,
	coalesce(fc.vl_cs_post_sale * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_cs_post_sale = 1) 
				over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_cs_post_sale) as vl_cs_post_sale,
    fc.flg_expected_cs_post_sale,
	coalesce(fc.vl_collection * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_collection = 1) 
				over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_collection) as vl_collection,
    fc.flg_expected_collection,
	coalesce(fc.vl_bo_onboarding * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_bo_onboarding = 1) 
				over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_bo_onboarding) as vl_bo_onboarding,
    fc.flg_expected_bo_onboarding,
	coalesce(fc.vl_bo_ongoing * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_bo_ongoing = 1) 
				over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_bo_ongoing) as vl_bo_ongoing,
    fc.flg_expected_bo_ongoing,
	coalesce(fc.vl_bo_offboarding * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_bo_offboarding = 1) 
				over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_bo_offboarding) as vl_bo_offboarding,
    fc.flg_expected_bo_offboarding,
	coalesce(fc.vl_inspections * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_inspection = 1) 
				over (partition by fc.sk_property, fc.sk_contract rows between unbounded preceding and current row)), fc.vl_inspections) as vl_inspections,
    fc.flg_expected_inspection,
	coalesce(fc.vl_insurance_fee * (1 - sum(cf.loss_factor) 
			filter (where fc.flg_expected_insurance_fee = 1) 
				over (partition by fc.sk_property, sk_contract rows between unbounded preceding and current row)), fc.vl_insurance_fee) as vl_insurance_fee,
    fc.flg_expected_insurance_fee
from fact_contract fc
left join unit_economics.contract_factor cf
	on cf.months_after_signature = fc.months_diff
;
