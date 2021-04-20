with
    region_info as (
        select distinct
            region_code,
            city_group
        from dim_region
        where region_code > 0
    ),
    agents_hours as ( -- information about allocated slots and agents available hours
        select
            faha.sk_agent,
            du.id as sk_user_agent,
            faha.area,
            ri.city_group,
            dd.date,
            dd.week_start,
            sum(faha.allocated_slots_0 / 4.00) as hours_available,
            sum(faha.is_allocation_available::int) as max_hours_available
        from agent.fact_agent_hourly_allocations faha
        left join dim_date dd
            on dd.sk_date = faha.sk_slot_date
        left join region_info ri
            on ri.region_code = faha.area
        left join dim_user du
            on du.dados_agente_id = faha.sk_agent
        where faha.is_allocation_available = true
            and dd.date > date('2017-12-31') and dd.week_start <= date_trunc('week', current_date)
            and area != -1
        group by 1,2,3,4,5,6
        ),
    agents_info as (
        select
            id,
            data_ativacao,
            status
        from datalake_raw.gsheets_aux_agents
        where data_ativacao != ''
    ),
    agents_visits_booked_info as ( -- information about visits, offers, proposals and contracts
        select distinct
            rf.sk_rent_flow,
            rf.sk_booking,
            rf.sk_user_agent,
            du.dados_agente_id as sk_agent,
            dd.date,
            dd.week_start,
            rf.sk_client,
            rf.flg_visit_completed,
            db.first_update_source,
            db.cancellation_reason_category,
            db.troublesome_entrance,
            db.agent_arrived,
            db.dt_cancel,
            dar.rating,
            rf.sk_offer,
            rf.sk_proposal,
            rf.sk_contract,
            rf.sk_visit_date,
            dd.date as visit_date,
            rf.sk_offer_submitted_date,
            dd1.date as offer_submitted_date,
            rf.sk_offer_approved_date,
            dd2.date as offer_approved_date,
            rf.sk_tenant_first_doc_sent_date,
            dd3.date as tenant_first_doc_sent_date,
            rf.sk_credit_analysis_approved_date,
            dd4.date as credit_analysis_approved_date,
            rf.sk_contract_signed_date,
            dd5.date as contract_signed_date,
            dof.last_offered_rent
        from fact_listing_rent_flows rf
        left join dim_booking db
            on db.sk_booking = rf.sk_booking
        left join dim_offer dof
            on dof.sk_offer = rf.sk_offer
        left join dim_user du
            on du.id = rf.sk_user_agent
        left join dim_date dd
            on dd.sk_date = rf.sk_visit_date
        left join dim_date dd1
            on dd1.sk_date = rf.sk_offer_submitted_date
        left join dim_date dd2
            on dd2.sk_date = rf.sk_offer_approved_date
        left join dim_date dd3
            on dd3.sk_date = rf.sk_tenant_first_doc_sent_date
        left join dim_date dd4
            on dd4.sk_date = rf.sk_credit_analysis_approved_date
        left join dim_date dd5
            on dd5.sk_date = rf.sk_contract_signed_date
        left join dim_agent_review dar
            on dar.sk_booking = rf.sk_booking
        where dd.date > date('2017-12-31')
            and rf.sk_booking > 0
        ),
    agents_funnel_base as ( -- consolidated base about rent funnel informations
        select
            sk_agent,
            week_start,
            date as event_date,
            count(distinct sk_booking) as visits_booked,
            count(distinct case when sk_booking > 0 then sk_client end) as visits_booked_user,
            count(distinct case when sk_booking > 0 and first_update_source = 'Corretores' then sk_booking end) as vb_by_agent,
            count(distinct case when sk_booking > 0 and first_update_source = 'Corretores' then sk_client end) as vb_by_agent_user,
            count(distinct case when flg_visit_completed = true then sk_booking end) as visits_completed,
            count(distinct case when flg_visit_completed = true then sk_client end) as visits_completed_user,
            count(distinct case when dt_cancel is not null then sk_booking end) as visits_canceled,
            count(distinct case when dt_cancel is not null then sk_client end) as visits_canceled_user,
            count(distinct case when flg_visit_completed = 0 and cancellation_reason_category = 'Agent' then sk_booking end) as cancel_by_agent,
            count(distinct case when flg_visit_completed = 0 and cancellation_reason_category = 'Agent' then sk_client end) as cancel_by_agent_user,
            count(distinct case when flg_visit_completed = 0 and cancellation_reason_category is null and troublesome_entrance is null and agent_arrived = 0 then sk_booking end) as no_show_by_agent,
            count(distinct case when flg_visit_completed = 0 and cancellation_reason_category is null and troublesome_entrance is null and agent_arrived = 0 then sk_client end) as no_show_by_agent_user,
            count(distinct case when sk_offer > 0 and date_diff('days',offer_submitted_date, date) <= 14 then sk_offer end) as offers_sent_14,
            count(distinct case when sk_offer > 0 and date_diff('days',offer_submitted_date, date) <= 14 then sk_client end) as offers_sent_user_14,
            count(distinct case when sk_proposal > 0 and date_diff('days',offer_approved_date, date) <= 14 then sk_proposal end) as offers_approved_14,
            count(distinct case when sk_proposal > 0 and date_diff('days',offer_approved_date, date) <= 14 then sk_client end) as offers_approved_user_14,
            count(distinct case when sk_proposal > 0 and date_diff('days',tenant_first_doc_sent_date, date) <= 14 then sk_proposal end) as doc_sent_14,
            count(distinct case when sk_proposal > 0 and date_diff('days',credit_analysis_approved_date, date) <= 14 then sk_proposal end) as credit_approved_14,
            count(distinct case when sk_contract > 0 and date_diff('days',contract_signed_date, date) <= 14 then sk_contract end) as contract_signed_14,
            count(distinct case when sk_contract > 0 and date_diff('days',contract_signed_date, date) <= 14 then sk_client end) as contract_signed_user_14,
            avg(rating) as avg_review,
            sum(case when sk_contract_signed_date > 0 then last_offered_rent end) as ticket
        from agents_visits_booked_info
        group by 1,2,3
    ),
    agents_base as ( -- consolidated base with hours and rent funnel informations
    select
        ah.sk_agent,
        ah.sk_user_agent,
        ah.area,
        ah.city_group,
        ah.week_start,
        sum(ah.hours_available) as hours_available,
        sum(ah.max_hours_available) as max_hours_available,
        sum(afb.visits_booked) as visits_booked,
        sum(afb.visits_booked_user) as visits_booked_user,
        sum(vb_by_agent) as vb_by_agent,
        sum(vb_by_agent_user) as vb_by_agent_user,
        sum(afb.visits_completed) as visits_completed,
        sum(afb.visits_completed_user) as visits_completed_user,
        sum(afb.visits_canceled) as visits_canceled,
        sum(afb.visits_canceled_user) as visits_canceled_user,
        sum(afb.cancel_by_agent) as cancel_by_agent,
        sum(afb.cancel_by_agent_user) as cancel_by_agent_user,
        sum(no_show_by_agent) as no_show_by_agent,
        sum(no_show_by_agent_user) as no_show_by_agent_user,
        sum(afb.offers_sent_14) as offers_sent_14,
        sum(afb.offers_sent_user_14) as offers_sent_user_14,
        sum(afb.offers_approved_14) as offers_approved_14,
        sum(afb.offers_approved_user_14) as offers_approved_user_14,
        sum(afb.doc_sent_14) as doc_sent_14,
        sum(afb.credit_approved_14) as credit_approved_14,
        sum(afb.contract_signed_14) as contract_signed_14,
        sum(afb.contract_signed_user_14) as contract_signed_user_14,
        1.00 * nullif(sum(afb.contract_signed_14),0) / nullif(sum(afb.visits_booked),0) as vb2cs_14,
        1.00 * nullif(sum(afb.contract_signed_user_14),0) / nullif(sum(afb.visits_booked_user),0) as vb2cs_user_14,
        1.00 * nullif(sum(afb.contract_signed_14),0) / nullif(sum(afb.visits_completed),0) as vc2cs_14,
        1.00 * nullif(sum(afb.contract_signed_user_14),0) / nullif(sum(afb.visits_completed_user),0) as vc2cs_user_14,
        avg(avg_review) as avg_review,
        1.00 * sum(case when afb.contract_signed_14 > 0 then ticket end) / sum(case when afb.contract_signed_14 > 0 then contract_signed_14 end) as avg_ticket
    from agents_hours ah
    left join agents_funnel_base afb
        on afb.sk_agent = ah.sk_agent and afb.event_date = ah.date
    group by 1,2,3,4,5
    )
 select
    *,
    percent_rank() over (partition by area, week_start order by coalesce(vb2cs_14,0)) as pct_region_visit_booked_to_contract_signed,
    percent_rank() over (partition by area, week_start order by coalesce(vb2cs_user_14,0)) as pct_region_visit_booked_to_contract_signed_user,
    percent_rank() over (partition by city_group, week_start order by coalesce(vb2cs_14,0)) as pct_city_group_visit_booked_to_contract_signed,
    percent_rank() over (partition by city_group, week_start order by coalesce(vb2cs_user_14,0)) as pct_city_group_visit_booked_to_contract_signed_user
 from agents_base
where hours_available > 0
