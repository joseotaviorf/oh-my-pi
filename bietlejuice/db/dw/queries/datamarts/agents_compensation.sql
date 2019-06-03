with agent_contracts as (
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
                  else rent*"7_contract"
              end
              ) as agent_monthly_compensation
      from agent_contracts a
          join datalake_raw.agents_compensation_history ch
              on a.doc_signed_date between date(ch."init") and date(ch."end")
              and a.region_code = ch.region_code
      group by 1, 2, 3
    ),
    /*
     *   Hourly agent bonification
     */
    agent_hours_opened as (
      select
        du.sk_user as agent_id,
        dslot.month_start as month_hours_opened,
        ad.area as region_code,
        sum(ad.allocated_slots)/4 as hours_opened
      from agent.fact_agent_daily_allocations ad
        join dim_date dslot
          on dslot.sk_date = ad.sk_slot_date
        join dim_user du
          on du.dados_agente_id = ad.sk_agent
      group by 1, 2, 3
    ),
    agent_contracts_signed as (
      select
        rf.sk_user_agent as agent_id,
        dcontract.month_start as compensation_month,
        sum(hours_opened) as hours_opened,
        round(sum(dc.rent*hch.commission),2) as sum_rent_contracts_signed
      from agent_hours_opened ho
        join fact_listing_rent_flows rf
          on rf.sk_user_agent = ho.agent_id
        join dim_date dcontract
          on dcontract.sk_date = rf.sk_contract_signed_date
        join dim_contract dc
          on rf.sk_contract = dc.sk_contract
        join datalake_raw.agents_hourly_compensation_history hch
          on hch.region_code = ho.region_code
          and dcontract.date BETWEEN hch."init" and hch."end"
      group by 1, 2
    ),
    compensation_by_hour as (
      select distinct
        agent_id,
        compensation_month,
        'Hour' as compensation_type,
        round(sum_rent_contracts_signed + case when hours_opened > 80 then 2500 when hours_opened > 40 then 1200 else 0 end,2) as agent_monthly_compensation
      from agent_contracts_signed
    )
    select
      *
    from compensation_by_commission
    union all
    select
      *
    from compensation_by_hour