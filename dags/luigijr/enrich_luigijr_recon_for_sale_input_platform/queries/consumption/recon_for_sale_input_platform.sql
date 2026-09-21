with

sale_offer_init as (
select
    id_offer,
    id_house,
    date_add(hour, -3, ts_sale_agreement_signed) as ts_sale_agreement_signed, 
    date_add(hour, -3, ts_offer_canceled) as ts_offer_canceled, 
    date_add(hour, -3, ts_offer_rescued) as ts_offer_rescued, 
    date_add(hour, -3, ts_offer_dismissed) as ts_offer_dismissed,
    business_unit,
    tags_from_salesflow,
    coalesce(is_3p_supply, false) as is_3p_supply,
    coalesce(is_3p_demand, false) as is_3p_demand,
    cast(brokerage_fee as double) as brokerage_fee_sales,
    sum(sale_price_agreed) as sale_price_agreed_sales,
    sum(sale_price_agreed * cast(brokerage_fee as double)) as brokerage_amount_sales
from
    datalake_sale_offer.sale_offer
group by 1,2,3,4,5,6,7,8,9, 10, 11
)

,monopoly_sale_revision as (
select
    *
    ,max(
        case
            when brokerage_fee_monopoly <> lag_brokerage_fee_monopoly or brokerage_quintoandar_fee <> lag_brokerage_quintoandar_fee or brokerage_estate_agent_fee <> lag_brokerage_estate_agent_fee
                then ts_created
            else null
        end
    ) over(partition by id_external_offer) as ts_contract_amendment
from(
    select
        id_external_offer
        ,date_add(hour, -3, ts_created) as ts_created
        ,dt_signature
        ,case 
            when last_day(add_months(current_date, -1)) >= date(date_add(hour, -3, ts_cancelled))
                then date_add(hour, -3, ts_cancelled)
            else null
        end as ts_cancelled
        ,payment_model
        ,city
        ,category
        ,case
            when last_day(add_months(current_date, -1)) >= date(date_add(hour, -3, ts_payment_allowed)) 
                then date_add(hour, -3, ts_payment_allowed)
            else null
        end as ts_payment_allowed
        ,total_payment_amount as sale_price_agreed_monopoly
        ,brokerage_fee as brokerage_fee_monopoly
        ,total_payment_amount * brokerage_fee as brokerage_amount_monopoly
        ,brokerage_quintoandar_fee
        ,brokerage_estate_agent_fee
        ,lag(brokerage_fee) over(partition by id_external_offer order by ts_created) as lag_brokerage_fee_monopoly
        ,lag(brokerage_quintoandar_fee) over(partition by id_external_offer order by ts_created) as lag_brokerage_quintoandar_fee
        ,lag(brokerage_estate_agent_fee) over(partition by id_external_offer order by ts_created) as lag_brokerage_estate_agent_fee
        ,max(date_add(hour, -3, ts_created)) over(partition by id_external_offer) as max_ts_created
    from
        datalake_monopoly_clean.sale_revision
    where
        date(date_add(hour, -3, ts_created)) <= date_add(day, 2 ,last_day(add_months(current_date, -1)))
    )
where
    max_ts_created = ts_created
)

,discount_collections as (
select
    sr.id_external_offer as id_offer,
    ir.amount as discount,
    st.event
from 
    datalake_monopoly_clean.income_reference ir
inner join 
    datalake_monopoly_clean.sale_transaction st
    on st.id_income_reference = ir.id
inner join 
    datalake_monopoly_clean.sale s
    on s.id = st.id_sale
inner join 
    datalake_monopoly_clean.sale_revision sr
    on sr.id = s.id
   and sr.revision = s.current_revision
where 
    event in ('income-debt-forgiveness')
)

,third_party_demand as (
select
    id_offer_external as id_offer,
    round(sum(cast(get_json_object(json_output,'$["gross-remuneration"]') as double)),2) as partner_fee_value_demand
from 
    datalake_nazare_clean.revenue_share_by_participant
where 
    ts_invalidated is null
    and offer_category like '%DEMAND%'
    and get_json_object(
        json_output,
        '$["participant-role"]'
      ) in ('DEMAND', 'THIRD_PARTY_AGENT')
group by 1
)

,sale_offer as (
select
    r.id_offer,
    r.id_house,
    coalesce(r.ts_sale_agreement_signed, l.dt_signature) as ts_sale_agreement_signed, 
    case 
        when r.ts_offer_canceled < coalesce(r.ts_sale_agreement_signed, l.dt_signature) and l.ts_cancelled is null
            then null
        else r.ts_offer_canceled
    end as ts_offer_canceled,
    r.ts_offer_rescued,
    case 
        when r.ts_offer_dismissed < coalesce(r.ts_sale_agreement_signed, l.dt_signature) and l.ts_cancelled is null
            then null
        else r.ts_offer_dismissed
    end as ts_offer_dismissed,
    r.business_unit,
    r.tags_from_salesflow,
    case
        when date(coalesce(r.ts_sale_agreement_signed, l.dt_signature)) >= '2026-06-01'
            then r.is_3p_supply
        else false
    end as is_3p_supply,
    case
        when date(coalesce(r.ts_sale_agreement_signed, l.dt_signature)) >= '2026-06-01'
            then r.is_3p_demand
        else false
    end as is_3p_demand,
    case 
        when r.brokerage_fee_sales > 1 and l.brokerage_fee_monopoly < 1
            then l.brokerage_fee_monopoly
        when coalesce(r.brokerage_amount_sales, l.brokerage_amount_monopoly) = l.brokerage_amount_monopoly
            then l.brokerage_fee_monopoly
        else coalesce(r.brokerage_fee_sales, l.brokerage_fee_monopoly)
    end as brokerage_fee_sales,
    case
        when coalesce(r.brokerage_amount_sales, l.brokerage_amount_monopoly) = l.brokerage_amount_monopoly
            then l.sale_price_agreed_monopoly
        else coalesce(r.sale_price_agreed_sales, l.sale_price_agreed_monopoly) 
    end as sale_price_agreed_sales,
    case 
        when r.brokerage_fee_sales > 1 and l.brokerage_fee_monopoly < 1
            then l.brokerage_amount_monopoly
        else coalesce(r.brokerage_amount_sales, l.brokerage_amount_monopoly)
    end as brokerage_amount_sales,
    l.payment_model,
    l.ts_payment_allowed,
    l.ts_contract_amendment,
    coalesce(e.city_group, 'not_found') as city_group,
    case
        when e.city_group = 'RMSP'
            then 'L001'
        when e.city_group = 'Rio de Janeiro'
            then 'L002'
        when e.city_group = 'Belo Horizonte'
            then 'L003'
        when e.city_group = 'Brasília'
            then 'L004'
        when e.city_group = 'Goiânia'
            then 'L005'
        when e.city_group = 'Curitiba'
            then 'L006'
        when e.city_group = 'Porto Alegre'
            then 'L007'
        when e.city_group = 'Florianópolis'
            then 'L008'
        when e.city_group = 'Campinas'
            then 'L009'
        when e.city_group = 'Recife'
            then 'L010'
        when e.city_group = 'Salvador'
            then 'L011'
        when e.city_group = 'Santos'
            then 'L012'
        when e.city_group = 'Mogi das Cruzes'
            then 'L013'
        when e.city_group = 'São José dos Campos'
            then 'L014'
        when e.city_group = 'Cotia'
            then 'L015'
        when e.city_group = 'Vitória'
            then 'L016'
        when e.city_group = 'Ribeirão Preto'
            then 'L017'
        when e.city_group = 'Sorocaba'
            then 'L018'
        when e.city_group = 'Uberlândia'
            then 'L019'
        when e.city_group = 'São José do Rio Preto'
            then 'L020'
        when e.city_group = 'Fortaleza'
            then 'L021'
        when e.city_group = 'Belém'
            then 'L022'
        when e.city_group = 'Manaus'
            then 'L023'
        else 'not_found'
    end as location,
    coalesce(l.category, 'not_found') as category,
    case 
        when l.category = 'BM_3P_LEAD_GEN_3P_SUPPLY'       
            then '002S4X'
        when l.category = 'BM_3P_DEMAND_1P_SUPPLY'         
            then '002S4X'
        when l.category = 'BM_3P_DEMAND_3P_SUPPLY_6P'      
            then '002S4X'
        when l.category = 'BM_3P_LEAD_GEN_1P_SUPPLY'       
            then '002S4X'
        when l.category = '3P_DEMAND'                      
            then '002S4X'
        when l.category = 'BM_3P_LEAD_GEN_3P_SUPPLY_6P'    
            then '002S4X'
        when l.category = 'BM_3P_SUPPLY_1P_DEMAND_AGENT'  
            then '002S3X'
        when l.category = 'BM_3P_DEMAND_3P_SUPPLY'         
            then '002S4X'
        when l.category = '3P_SUPPLY'                      
            then '002S3X'
        when l.category = '1P'                             
            then '002S2X'
        when l.category = 'BM_1P'                          
            then '002S2X'
        else 'not_found'
    end as cost_center,
    coalesce(l.sale_price_agreed_monopoly, 0) as sale_price_agreed_monopoly,
    coalesce(l.brokerage_fee_monopoly, 0) as brokerage_fee_monopoly,
    coalesce(l.brokerage_amount_monopoly, 0) as brokerage_amount_monopoly,
    coalesce(l.brokerage_quintoandar_fee, 0) as brokerage_quintoandar_fee,
    coalesce(l.brokerage_estate_agent_fee, 0) as brokerage_estate_agent_fee,
    coalesce(c.partner_fee_value_demand, 0) as partner_fee_value_demand
from
    sale_offer_init as r
left join
    monopoly_sale_revision as l
    on r.id_offer = l.id_external_offer
left join
    third_party_demand as c
    on r.id_offer = c.id_offer
left join
    dw_sale.fact_offers as d
    on r.id_offer = d.sk_offer
left join
    (select distinct sk_region, city_group from dw_public.dim_region) as e
    on d.sk_region = e.sk_region
where
    date(coalesce(r.ts_sale_agreement_signed, l.dt_signature)) <= date_add(day, 2, last_day(add_months(current_date, -1)))
)

,dd_date as (
select distinct
    fcf.sk_offer, 
    legal_end.date as dt_legal_analysis
from
    dw_sale.fact_closing_flows as fcf
left join
    dw_public.dim_date as legal_end
    on fcf.sk_legal_analysis_ended_date = legal_end.sk_date
where
    date(legal_end.date) <= last_day(add_months(current_date, -1))
)

,offer_canceled as(
select distinct
    r.ts_created, 
    r.id_ccv_termination, 
    r.id_sales_flow, 
    l.id_firestore as sk_offer, 
    r.condition,
    r.payer_type
from 
    datalake_sales_flow_clean.ccv_termination as r 
left join 
    datalake_sales_flow_clean.offer as l 
    on r.id_sales_flow = l.id_sales_flow
where
    date(r.ts_created) <= last_day(add_months(current_date, -1))
)

,monopoly_cash_flow as (
select
    s.id_external_offer as sk_offer,
    date(st.dt_accounting) as dt_reference,
    'monopoly' as table_info,
    st.description as description,
    st.status,
    case
        when i.id is null 
            then 'MANUAL'
        else 'AUTOMATICO'
    end as origem_entrada,
    st.ts_created,
    coalesce(ae.debit,0) - coalesce(ae.credit,0) as amount
from
    datalake_monopoly_clean.accounting_entry as ae
left join
    datalake_monopoly_clean.sale_transaction as st
    on ae.id_sale_transaction = st.id
left join
    datalake_monopoly_clean.sale as s
    on st.id_sale = s.id
left join 
    datalake_monopoly_clean.income_reference as i 
    on i.id = st.id
where 
    (st.id_income_reference is not null or st.id_outcome_reference is not null)
    and ae.person_type = 'quintoandar'
)

,robin_hood_cash_flow as (
select
    ae.id_offer as sk_offer,
    ae.dt_occurrence as dt_reference,
    'robin_hood' as table_info,
    aes.description as description,
    'created' as status,
    upper(type) as origem_entrada,
    ae.ts_created,
    case
        when ae.cost_center_code = 'S01402' and upper(type) = 'STANDARD' and aes.description = 'Pagamentos relacionados aos corretores for sale'
            then -1*ae.due_amount
        when ae.cost_center_code in ('C097', 'C046', 'C121')
            then -1*ae.due_amount
        else 0
    end as amount
            
from 
    datalake_robin_hood.accounting_entry as ae
inner join 
    datalake_robin_hood_clean.accounting_entry_source as aes 
    on aes.id = ae.id_source
where
    ae.id_source in (7, 10)
    and aes.source_name not like '%CIQ Campanhas%'
)

,cash_flow as (
select
    *
    ,max(dt_reference) over(partition by sk_offer) as max_dt_reference
    ,case 
        when sum(
                case
                    when lower(description) not like '%corretor%' and status <> 'reversed'
                        then 0
                    when status = 'reversed'
                        then 0            
                    else amount
                end) over(partition by sk_offer) <= 0 and status = 'reversed'
            then 0
        else amount
    end as accounting_entry_broker
    ,amount as accounting_entry
from(
    select * from monopoly_cash_flow
    
    union all
     
    select * from robin_hood_cash_flow
    )
where
    date(dt_reference) <= last_day(add_months(current_date, -1))
)

,categorical_cash_flow as (
select
    sk_offer
    ,max_dt_reference
    ,sum(accounting_entry) as accounting_entry
    ,sum(
        case
            when lower(description) like '%corretor%' or lower(description) like '%band-aid%'
                then 0
            else accounting_entry
        end
    ) as total_received
    ,sum(
        case
            when lower(description) not like '%corretor%' and status <> 'reversed'
                then 0
            -- when status = 'reversed'
            --     then 0            
            else -accounting_entry_broker
        end
    ) as broker_payment
    ,sum(
        case
            when lower(description) not like '%band-aid%'
                then 0
            else accounting_entry
        end
    ) as band_aid_cost
from
    cash_flow
where
    date(max_dt_reference) <= last_day(add_months(current_date, -1))
group by 1,2
)
      
,payment_current_entries as (
select 
    get_json_object(ae.metadata, '$["offer-id"]') as id_offer,
    get_json_object(ae.metadata, '$["house-id"]') as id_house,
    ae.due_amount,
    date(pr.dt_paid) as dt_paid
from 
    datalake_robin_hood_clean.accounting_entry as ae
left join 
    datalake_robin_hood_clean.accounting_entry_balance as aeb 
    on ae.id = aeb.id_accounting_entry
left join 
    datalake_robin_hood_clean.payment_request as pr 
    on pr.id = aeb.id_payment_request
left join 
    datalake_robin_hood_clean.payee as p 
    on p.id = ae.id_payee
where 
    ae.id_source = 10
    and date(ae.ts_created) <= last_day(add_months(current_date, -1))
    and (date(pr.dt_paid) <= last_day(add_months(current_date, -1)) or pr.dt_paid is null)
    and pr.id_next_attempt is null
)

,payment as (
select 
    id_offer,
    sum(case when due_amount > 0 and dt_paid is null then due_amount else 0 end) as broker_payment_with_null_date,
    sum(case when dt_paid is not null then due_amount else 0 end) as broker_payment_robin_hood,
    sum(case when due_amount < 0 and dt_paid is null then due_amount else 0 end) as broker_discount
from
    payment_current_entries
-- where 
--     due_amount < 0 and dt_paid is null
group by 1
)

,invoices as (
select 
    l.id_business_entity as id_offer,
    max(l.dt_reference) as max_dt_reference
from 
    datalake_pas.ledger as l
where 
    l.dt_reference <= last_day(add_months(current_date, -1))
    and l.id_business_entity is not null
    and try_cast(l.id_business_entity as int) is null
    and l.account_number in ('420008', '420007', '420024')
group by 1
)

,offer_legal_entity as (
select distinct
  get_json_object(fr.reference_properties, '$.offerid') as id_offer
  ,true as is_legal_entity
from 
  datalake_docx_clean.folder_reference as fr
left join 
  datalake_docx_clean.folder_reference_type as frt
  on frt.id = fr.id_folder_reference_type
left join 
  datalake_docx_clean.document as d
  on d.id_folder = fr.id_source_folder
left join 
  datalake_docx_clean.document_type as dt
  on dt.id = d.id_document_type
where
    (frt.id = 21 or frt.id = 22)
    and dt.id = 7
)

,offer_union as (
select id_offer from sale_offer

union 

select sk_offer as id_offer from offer_canceled

union

select sk_offer as id_offer from categorical_cash_flow

union

select sk_offer as id_offer from dd_date

union

select id_offer from invoices
)

,offer_full as (
select
    r.id_offer
    ,l.id_house
    ,round(coalesce(l.sale_price_agreed_sales,0),2) as sale_price_agreed_sales
    ,round(coalesce(l.brokerage_amount_sales,0),2) as brokerage_amount_sales
    ,coalesce(l.brokerage_fee_sales,0) as brokerage_fee_sales
    ,l.business_unit
    ,case
        when lower(l.business_unit) like '%mg%'
            then 'casa_mineira'
        when lower(l.business_unit) like '%bh%'
            then 'casa_mineira'
        else 'plataforma'
    end as business_unit_description
    ,l.tags_from_salesflow
    ,case
        when lower(l.tags_from_salesflow) like '%aditivo%'
            then true
        when l.ts_contract_amendment is not null
            then true
        else false
    end as is_contract_amendment
    ,coalesce(l.cost_center, 'not_found') as cost_center
    ,coalesce(l.location, 'not_found') as location 
    ,round(coalesce(l.sale_price_agreed_monopoly,0),2) as sale_price_agreed_monopoly
    ,round(coalesce(l.brokerage_amount_monopoly,0),2) as brokerage_amount_monopoly
    ,coalesce(l.brokerage_fee_monopoly,0) as brokerage_fee_monopoly
    ,l.payment_model as payment_model
    ,round(coalesce(l.sale_price_agreed_sales,0),2) as sale_price_agreed
    ,round(coalesce(l.brokerage_amount_sales,0),2) as brokerage_amount
    ,coalesce(l.brokerage_fee_sales,0) as brokerage_fee
    ,coalesce(l.brokerage_quintoandar_fee,0) as brokerage_quinto_andar_fee
    ,coalesce(l.brokerage_quintoandar_fee,0) * coalesce(l.brokerage_amount_sales,0) as brokerage_quinto_andar_amount
    ,coalesce(l.brokerage_estate_agent_fee,0) as brokerage_estate_agent_fee
    ,coalesce(l.brokerage_estate_agent_fee,0) * coalesce(l.brokerage_amount_sales,0) as brokerage_estate_agent_amount
    ,coalesce(l.partner_fee_value_demand, 0) as partner_fee_value_demand
    ,l.ts_payment_allowed as dt_payment_allowed
    ,coalesce(l.is_3p_supply, False) as is_3p_supply
    ,coalesce(l.is_3p_demand, False) as is_3p_demand 
    ,date(l.ts_sale_agreement_signed) as dt_sale_agreement_signed
    ,case
        when date(l.ts_offer_rescued) <= last_day(add_months(current_date, -1))
            then date(l.ts_offer_rescued)
        else null
    end as dt_rescued
    ,case 
        when date(coalesce(c.ts_created, l.ts_offer_canceled, l.ts_offer_dismissed)) <= last_day(add_months(current_date, -1)) 
            then date(coalesce(c.ts_created, l.ts_offer_canceled, l.ts_offer_dismissed)) 
        else null 
    end as dt_cancelled
    ,c.condition as condition
    ,date(d.max_dt_reference) as dt_accounting_entry
    ,round(coalesce(d.total_received,0),2) as total_received
    ,round(coalesce(d.broker_payment,0),2) as broker_payment_accounting_entry
    ,round(coalesce(g.broker_payment_robin_hood,0),2) as broker_payment_robin_hood
    ,round(coalesce(g.broker_payment_with_null_date,0),2) as broker_payment_with_null_date
    ,round(coalesce(g.broker_discount,0),2) as broker_discount
    ,round(coalesce(d.band_aid_cost,0),2) band_aid_cost
    ,date(
    case 
        when l.payment_model = 'brokerage-term' 
            then l.ts_sale_agreement_signed 
        else e.dt_legal_analysis 
    end
    ) as dt_legal_analysis
    ,date(f.max_dt_reference) as dt_reference_ledger
    ,coalesce(i.is_legal_entity, false) as is_legal_entity
    ,date(greatest(coalesce(date(c.ts_created), date('1000-01-01')), coalesce(date(e.dt_legal_analysis), date('1000-01-01')), coalesce(date(d.max_dt_reference), date('1000-01-01')), coalesce(date(f.max_dt_reference), date('1000-01-01')))) as dt_recon
from
    offer_union as r
left join
    sale_offer as l
    on r.id_offer = l.id_offer
left join
    offer_canceled as c
    on r.id_offer = c.sk_offer
left join
    categorical_cash_flow as d
    on r.id_offer = d.sk_offer
left join
    dd_date as e
    on r.id_offer = e.sk_offer
left join 
    invoices as f
    on r.id_offer = f.id_offer
left join
    payment as g
    on r.id_offer = g.id_offer
left join 
    offer_legal_entity as i
    on r.id_offer = i.id_offer
)

select
    id_offer
    ,id_house
    ,dt_recon
    ,dt_legal_analysis
    ,dt_cancelled
    ,dt_rescued
    ,dt_accounting_entry
    ,dt_sale_agreement_signed
    ,dt_payment_allowed
    ,business_unit_description
    ,payment_model
    ,is_contract_amendment
    ,is_legal_entity
    ,cost_center
    ,location
    ,case
        when is_3p_demand = true
            then 'demand'
        when is_3p_supply = true
            then 'supply'
        else 'not_marketplace'
    end as supply_x_demand
    ,case 
        when condition = 'WITH_BROKERAGE'
            then true
        else
            false
    end as cancellation_brokerage
    ,case
        when coalesce(date(dt_rescued), date('1000-01-01')) < coalesce(date(dt_cancelled), date('1000-01-01'))
            then true
        else false
    end as offer_cancelled
    ,sale_price_agreed_sales
    ,brokerage_fee_sales
    ,sale_price_agreed_monopoly
    ,brokerage_fee_monopoly
    ,sale_price_agreed
    ,case 
        when is_3p_demand = True
            then brokerage_quinto_andar_amount + (brokerage_estate_agent_amount - partner_fee_value_demand)
        else
            brokerage_amount
    end as brokerage_amount
    ,brokerage_fee
    ,brokerage_quinto_andar_amount
    ,brokerage_quinto_andar_fee
    ,case 
        when is_3p_demand = True
            then partner_fee_value_demand
        else
            0
    end as partner_fee_value_demand
    ,case 
        when is_3p_demand = True 
            then (brokerage_estate_agent_amount - partner_fee_value_demand)
        else
            brokerage_estate_agent_amount
    end as brokerage_estate_agent_amount
    ,brokerage_estate_agent_fee
    ,total_received
    ,broker_payment_robin_hood
    ,broker_payment_accounting_entry
    ,case
        when broker_payment_with_null_date <> 0
            then broker_payment_robin_hood 
        when abs(broker_payment_robin_hood - case when is_3p_demand = True then (brokerage_estate_agent_amount - partner_fee_value_demand) else brokerage_estate_agent_amount end)
            < abs(broker_payment_accounting_entry - case when is_3p_demand = True then (brokerage_estate_agent_amount - partner_fee_value_demand) else brokerage_estate_agent_amount end)
            then broker_payment_robin_hood
        else broker_payment_accounting_entry
    end as broker_payment
    ,broker_discount
    ,band_aid_cost
from 
    offer_full
where 
    date(dt_recon) <= last_day(add_months(current_date, -1))
