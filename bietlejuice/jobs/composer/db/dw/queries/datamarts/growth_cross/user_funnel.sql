with
talk_to_agent AS (
    SELECT
        tta.tenant_id::INT AS sk_client,
        fhl.sk_region,
        TO_CHAR(first_message_ts::TIMESTAMP, 'YYYYMMDD')::INT AS sk_talk_to_agent_date
    FROM datamarts.talk_to_agent AS tta
        JOIN fact_house_listings AS fhl
          ON tta.sk_house_listing = fhl.sk_house_listing
    WHERE
        tta.business_context = 'RENT'
        AND tta.first_message_ts IS NOT NULL
), events_user as (
select
        COALESCE(rf.sk_client, ta.sk_client) AS sk_client,
        dr.city_group,
        sk_booking_created_date,
        sk_visit_date,
        flg_visit_completed,
        sk_reservation_created_date,
        sk_offer_submitted_date,
        sk_offer_approved_date,
        sk_tenant_first_doc_sent_date,
        sk_tenant_doc_complete_date as sk_tenant_doc_complete_date_old,
        coalesce(coalesce(nullif(sk_tenant_doc_complete_date,-1),nullif(sk_credit_analysis_init_date,-1)),-1) as sk_tenant_doc_complete_date,
        sk_credit_analysis_init_date,
        sk_credit_analysis_approved_date,
        sk_credit_analysis_end_date,
        sk_contract_created_date,
        sk_contract_signed_date,
        sk_talk_to_agent_date,
-- order of events
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_booking_created_date,-1)) as order_booking_created,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_visit_date,-1) asc, flg_visit_completed desc) as order_visit,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_reservation_created_date,-1)) as order_reservation,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_offer_submitted_date,-1)) as order_offer_submitted,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_offer_approved_date,-1)) as order_offer_approved,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_tenant_first_doc_sent_date,-1)) as order_tenant_first_doc_sent,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by coalesce(nullif(sk_tenant_doc_complete_date,-1),nullif(sk_credit_analysis_init_date,-1))) as order_tenant_doc_complete,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_credit_analysis_init_date,-1)) as order_credit_analysis_init,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_credit_analysis_approved_date,-1)) as order_credit_analysis_approved,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_credit_analysis_end_date,-1)) as order_credit_analysis_end,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_contract_created_date,-1)) as order_contract_created,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_contract_signed_date,-1)) as order_contract_signed,
        row_number() over(partition by COALESCE(rf.sk_client, ta.sk_client) order by nullif(sk_talk_to_agent_date,-1)) as order_talk_to_agent,
-- count of events
        sum(count(distinct case when sk_booking_created_date > 0 then sk_booking end)) over(partition by COALESCE(rf.sk_client, ta.sk_client)) as bookings_created,
        sum(count(distinct case when sk_visit_date > 0 and flg_visit_completed = true then sk_visit end)) over(partition by COALESCE(rf.sk_client, ta.sk_client)) as visits_completed,
        sum(count(distinct case when sk_offer_submitted_date > 0 then sk_offer end)) over(partition by COALESCE(rf.sk_client, ta.sk_client)) as offers_submitted,
        sum(count(distinct case when sk_offer_approved_date > 0 then sk_offer end)) over(partition by COALESCE(rf.sk_client, ta.sk_client)) as offers_approved,
        sum(count(distinct case when sk_reservation_created_date > 0 then sk_reservation end)) over(partition by COALESCE(rf.sk_client, ta.sk_client)) as reservations_created,
        sum(count(distinct case when sk_contract_signed_date > 0 then sk_contract end)) over(partition by COALESCE(rf.sk_client, ta.sk_client)) as contracts_signed
from fact_listing_rent_flows rf
full outer join talk_to_agent AS ta
    ON rf.sk_client = ta.sk_client AND rf.sk_region = ta.sk_region
left join dim_region dr
  on COALESCE(rf.sk_region, ta.sk_region) = dr.sk_region
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17
),
first_date_user as (
select
        sk_client,
        bookings_created,
        visits_completed,
        offers_submitted,
        offers_approved,
        reservations_created,
        contracts_signed,
        min(case when order_booking_created = 1 then city_group end) as first_city_group_booking,
    min(case when order_offer_submitted = 1 then city_group end) as first_city_group_offer,
        min(case when order_talk_to_agent = 1 then city_group end) as first_city_group_talk_to_agent,
        min(case when order_booking_created = 1 then sk_booking_created_date end) as first_booking_created_date,
        min(case when order_visit = 1 and flg_visit_completed = true then sk_visit_date end) as first_visit_date,
        min(case when order_reservation = 1 then sk_reservation_created_date end) as first_reservation_date,
        min(case when order_offer_submitted = 1 then sk_offer_submitted_date end) as first_offer_submitted_date,
        min(case when order_offer_approved = 1 then sk_offer_approved_date end) as first_offer_approved_date,
        min(case when order_tenant_first_doc_sent = 1 then sk_tenant_first_doc_sent_date end) as first_tenant_doc_sent_date,
        min(case when order_tenant_doc_complete = 1 then sk_tenant_doc_complete_date end) as first_tenant_doc_complete_date,
        min(case when order_credit_analysis_init = 1 then sk_credit_analysis_init_date end) as first_credit_analysis_init_date,
        min(case when order_credit_analysis_approved = 1 then sk_credit_analysis_approved_date end) as first_credit_analysis_approved_date,
        min(case when order_credit_analysis_end = 1 then sk_credit_analysis_end_date end) as first_credit_analysis_end_date,
        min(case when order_contract_created = 1 then sk_contract_created_date end) as first_contract_created_date,
        min(case when order_contract_signed = 1 then sk_contract_signed_date end) as first_contract_signed_date,
        min(case when order_talk_to_agent = 1 then sk_talk_to_agent_date end) as first_talk_to_agent_date
from events_user
group by 1, 2, 3, 4, 5, 6, 7
),
users_funnel as (
select
        sk_client as id_user,
        bookings_created,
        visits_completed,
        offers_submitted,
        offers_approved,
        reservations_created,
        contracts_signed,
        coalesce(coalesce(nullif(first_city_group_booking,-1),nullif(first_city_group_offer,-1), nullif(first_city_group_talk_to_agent,-1)),'-1') as first_city_group,
    case when nullif(first_booking_created_date,-1) is null and nullif(first_talk_to_agent_date,-1) is null and nullif(first_offer_submitted_date,-1) is not null then 'Offer'
         when nullif(first_booking_created_date,-1) is not null and nullif(first_talk_to_agent_date,-1) is null and nullif(first_offer_submitted_date,-1) is null then 'Booking'
         when nullif(first_booking_created_date,-1) is null and nullif(first_talk_to_agent_date,-1) is not null and nullif(first_offer_submitted_date,-1) is null then 'Talk to Agent'
         when date(nullif(first_booking_created_date,-1)) = LEAST(date(nullif(first_booking_created_date,-1)), date(nullif(first_offer_submitted_date,-1)), date(nullif(first_talk_to_agent_date,-1))) then 'Booking'
         when date(nullif(first_offer_submitted_date,-1)) = LEAST(date(nullif(first_booking_created_date,-1)), date(nullif(first_offer_submitted_date,-1)), date(nullif(first_talk_to_agent_date,-1))) then 'Offer'
         when date(nullif(first_talk_to_agent_date,-1)) = LEAST(date(nullif(first_booking_created_date,-1)), date(nullif(first_offer_submitted_date,-1)), date(nullif(first_talk_to_agent_date,-1))) then 'Talk to Agent'
    end as first_interaction,
        date(nullif(first_booking_created_date,'-1')) as first_booking_created_date,
        date(nullif(first_visit_date,'-1')) as first_visit_date,
        date(nullif(first_reservation_date,'-1')) as first_reservation_date,
        date(nullif(first_offer_submitted_date,'-1')) as first_offer_submitted_date,
        date(nullif(first_offer_approved_date,'-1')) as first_offer_approved_date,
        date(nullif(first_tenant_doc_sent_date,'-1')) as first_tenant_doc_sent_date,
        date(nullif(first_tenant_doc_complete_date,'-1')) as first_tenant_doc_complete_date,
        date(nullif(first_credit_analysis_init_date,'-1')) as first_credit_analysis_init_date,
        date(nullif(first_credit_analysis_approved_date,'-1')) as first_credit_analysis_approved_date,
        date(nullif(first_credit_analysis_end_date,'-1')) as first_credit_analysis_end_date,
        date(nullif(first_contract_created_date,'-1')) as first_contract_created_date,
        date(nullif(first_contract_signed_date,'-1')) as first_contract_signed_date,
        date(nullif(first_talk_to_agent_date,'-1')) as first_talk_to_agent_date
from first_date_user
),
days_user as (
select
    id_user,
        bookings_created,
        visits_completed,
        offers_submitted,
        offers_approved,
        reservations_created,
        contracts_signed,
    first_city_group,
    first_interaction,
    first_booking_created_date,
    first_visit_date,
    first_reservation_date,
    first_offer_submitted_date,
    first_offer_approved_date,
    first_tenant_doc_sent_date,
    first_tenant_doc_complete_date,
    first_credit_analysis_init_date,
    first_credit_analysis_approved_date,
    first_credit_analysis_end_date,
    first_contract_created_date,
    first_contract_signed_date,
    first_talk_to_agent_date,
    -- diff days
        datediff(day,first_booking_created_date,first_visit_date) as days_VB_VC,
        datediff(day,first_visit_date,first_offer_submitted_date) as days_VC_OS,
        datediff(day,first_offer_submitted_date,first_offer_approved_date) as days_OS_OA,
        datediff(day,first_offer_approved_date,first_tenant_doc_sent_date) as days_OA_DS,
        datediff(day,first_tenant_doc_sent_date,first_credit_analysis_approved_date) as days_DS_CA,
        datediff(day,first_credit_analysis_approved_date,first_contract_created_date) as days_CA_CC,
        datediff(day,first_contract_created_date,first_contract_signed_date) as days_CC_CS,
        -- diff week (diff related do week start for each event)
        datediff(week,date_trunc('week',first_booking_created_date),date_trunc('week',first_visit_date)) as week_VB_VC,
        datediff(week,date_trunc('week',first_visit_date),date_trunc('week',first_offer_submitted_date)) as week_VC_OS,
        datediff(week,date_trunc('week',first_offer_submitted_date),date_trunc('week',first_offer_approved_date)) as week_OS_OA,
        datediff(week,date_trunc('week',first_offer_approved_date),date_trunc('week',first_tenant_doc_sent_date)) as week_OA_DS,
        datediff(week,date_trunc('week',first_tenant_doc_sent_date),date_trunc('week',first_credit_analysis_approved_date)) as week_DS_CA,
        datediff(week,date_trunc('week',first_credit_analysis_approved_date),date_trunc('week',first_contract_signed_date)) as week_CA_CS
from users_funnel
)
select *
from days_user;