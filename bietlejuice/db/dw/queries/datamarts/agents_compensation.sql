/*
 * Old Compensation
 */
with old_compensation_by_visit as (
--	get total visits performed by agent on visit cohort
	select 
		rf.sk_user_agent,
		dd.month_start as compensation_month,
		count(distinct case when flg_visit_performed = 1 then sk_booking end) as visits_performed
	from fact_listing_rent_flows rf
		join dim_region dr	
			on dr.sk_region = rf.sk_region
		join dim_date dd
			on dd.sk_date = rf.sk_visit_date
		left join datalake_raw.gsheet_agents_hourly_compensation ch
			on dr.region_code = ch.region_code
	where ch.region_code is null
	group by 1, 2
),
old_compensation_by_contract as (
-- get total contracts signed by agent visit on contract signed cohort
	select 
		rf.sk_user_agent,
		dd.month_start as compensation_month,
		sum(dc.rent) as contracts_signed
	from fact_listing_rent_flows rf
		join dim_region dr	
			on dr.sk_region = rf.sk_region
		join dim_date dd
			on dd.sk_date = rf.sk_contract_signed_date
		join dim_contract dc
			on dc.sk_contract = rf.sk_contract
			and rf.sk_contract_signed_date > 0
		left join datalake_raw.gsheet_agents_hourly_compensation ch
			on dr.region_code = ch.region_code
	where ch.region_code is null
	group by 1, 2
),
old_compensation as (
-- makes the sum of number of contracts made by agent and compensation due to visits
	select
		bv.sk_user_agent as sk_agent,
		bv.compensation_month,
		'Old Commission' as compensation_type,
		(coalesce(bv.visits_performed,0)*10.0 + coalesce(bc.contracts_signed,0)*0.2) as agent_monthly_compensation
	from old_compensation_by_visit bv
		left join old_compensation_by_contract bc
			on bv.sk_user_agent = bc.sk_user_agent
			and bv.compensation_month = bc.compensation_month
	where bv.compensation_month between '2019-01-01' and '2019-06-01'
),
/*
 *  New Comission
 */
agent_contracts as (
-- creates a rank of contracts signed by agent
    select
        rf.sk_user_agent as agent_id,
        rf.sk_contract as contract_id,
        dca.month_start as doc_signed_month,
        dca.date as doc_signed_date,
        dc.rent,
        dr.region_code,
        rank() over (partition by sk_user_agent, dca.month_start order by dc.ts_signature) as contract_rnk
    from fact_listing_rent_flows rf
        join dim_date dca
            on dca.sk_date = rf.sk_contract_signed_date
            and sk_contract_signed_date > 0
        join dim_contract dc
            on dc.sk_contract = rf.sk_contract
        join dim_user du
            on du.sk_user = rf.sk_user_agent
            and rf.sk_user_agent > 0
        join fact_house_listings fhl
            on rf.sk_house_listing = fhl.sk_house_listing
        join dim_region dr
            on fhl.sk_region = dr.sk_region
    where
        dca.month_start >= '2019-03-01'
    ),
    compensation_by_commission as (
-- multiply contract by due comission
      select
          a.agent_id,
          a.doc_signed_month as compensation_month,
          'Commission' as compensation_type,
          sum(
              case
                  when contract_rnk = 1 then rent*"1_contract"
                  when contract_rnk = 2 then rent*"2_contract"
                  when contract_rnk = 3 then rent*"3_contract"
                  when contract_rnk = 4 then rent*"4_contract"
                  when contract_rnk = 5 then rent*"5_contract"
                  when contract_rnk = 6 then rent*"6_contract"
                  else rent*"7_or_more__contract"
              end
              ) as agent_monthly_compensation
      from agent_contracts a
          join datalake_raw.gsheet_agents_compensation ch
              on a.doc_signed_date between date(ch."dt_init") and date(ch."dt_end")
              and a.region_code = ch.region_code
      group by 1, 2, 3
    ),
    /*
     *   Hourly agent bonification
     */
    agent_hours_opened as (
    -- calculate the number of hours opened by month, agent and region
		select
		  du.sk_user as agent_id,
		  dslot.month_start as month_hours_opened,
		  da.area as region_code,
		  sum(da.allocated_slots)/4 as hours_opened
		from agent.fact_agent_daily_allocations da
			join dim_date dslot
		  		on dslot.sk_date = da.sk_slot_date
			join dim_user du
		  		on du.dados_agente_id = da.sk_agent
		where dslot.date > '2019-01-01'
		group by 1, 2, 3
    ),
    agent_region as (
    -- define the agent region by the one with the most hours opened (excluding region -1)
	    select
		    agent_id,
		    month_hours_opened,
		    region_code,
		    row_number() over (partition by agent_id, month_hours_opened order by hours_opened desc) as rnk_hours
		from agent_hours_opened 
		where region_code != -1
	),
	agent_hours as (
	-- calculate the sum of hours opened and allocate the agent to the region on the last coma
		select
			ar.agent_id,
			ar.month_hours_opened,
			ar.region_code,
			sum(hours_opened) as hours_opened
		from agent_hours_opened ho
			join agent_region ar
				on ho.agent_id = ar.agent_id
				and ho.month_hours_opened = ar.month_hours_opened
				and ar.rnk_hours = 1
		group by 1, 2, 3
	),
	agent_contracts_signed as (
	-- sum of rent signed due to agent visit
		select
			rf.sk_user_agent as agent_id,
			dcontract.month_start as contract_signed_month,
			sum(dc.rent) as sum_rent_signed
		from public.fact_listing_rent_flows rf
			join dim_date dcontract
				on dcontract.sk_date = rf.sk_contract_signed_date
				and rf.sk_contract_signed_date > 0
			join dim_contract dc
				on rf.sk_contract = dc.sk_contract
		group by 1, 2	
	),
	compensation_by_hour as (
	-- aggregate compensation by hours opened and contracts signed
		select
			ah.agent_id,
			ah.month_hours_opened as compensation_month,
			'Hour' as compensation_type,
			case 
				when ah.hours_opened > 80 then 2500
				when ah.hours_opened > 40 then 1200
				else 0
			end + coalesce(cs.sum_rent_signed,0)*ch.commission as agent_monthly_compensation
		from agent_hours ah
			left join agent_contracts_signed cs
				on ah.agent_id = cs.agent_id
				and ah.month_hours_opened = cs.contract_signed_month
			join datalake_raw.gsheet_agents_hourly_compensation ch
				on trim(ah.region_code) = trim(ch.region_code)			
				and ah.month_hours_opened between ch.dt_init and ch.dt_end
	)
select
  *
from compensation_by_commission
union all
select
  *
from compensation_by_hour
union all
select
    *
from old_compensation
