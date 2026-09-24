-- Databricks notebook source

with

input_platform as (
select
    id_offer
    ,id_house
    ,dt_recon as dt_recon_platform
    ,dt_legal_analysis as dt_legal_analysis_platform
    ,dt_cancelled
    ,dt_rescued
    ,dt_accounting_entry
    ,dt_sale_agreement_signed
    ,dt_payment_allowed
    ,business_unit_description
    ,payment_model
    ,is_contract_amendment
    ,is_legal_entity
    ,cost_center as cost_center_platform
    ,location
    ,supply_x_demand as supply_x_demand_platform
    ,cancellation_brokerage
    ,offer_cancelled
    ,sale_price_agreed_sales
    ,brokerage_fee_sales
    ,sale_price_agreed_monopoly
    ,brokerage_fee_monopoly
    ,sale_price_agreed as sale_price_agreed_platform
    ,brokerage_amount as brokerage_amount_platform
    ,brokerage_fee as brokerage_fee_platform
    ,brokerage_quinto_andar_amount as brokerage_quinto_andar_amount_platform
    ,brokerage_quinto_andar_fee
    ,partner_fee_value_demand as partner_fee_value_demand_platform
    ,brokerage_estate_agent_amount as brokerage_estate_agent_amount_platform
    ,brokerage_estate_agent_fee
    ,total_received as total_received_platform
    ,broker_payment_robin_hood
    ,broker_payment_accounting_entry
    ,broker_payment as broker_payment_platform
    ,broker_discount as broker_discount_platform
    ,band_aid_cost
from 
    ops_fintech.recon_for_sale_input_platform
where
    id_offer is not null
)

,input_gsheets as (
select
    nullif(id_offer, '') as id_offer,
    cast(nullif(dt_reference_ledger, '') as date) as dt_reference_ledger,
    cast(replace(nullif(invoice_amount_current_period_sheet, ''), ',', '') as double) as invoice_amount_current_period,
    cast(replace(nullif(invoice_amount_sheet, ''), ',', '') as double) as invoice_amount,
    cast(replace(nullif(rede_payment, ''), ',', '') as double) as rede_payment,
    cast(replace(nullif(amount_indemnity_payment, ''), ',', '') as double) as amount_indemnity_payment,
    cast(nullif(dt_legal_analysis_demand, '') as date) as dt_legal_analysis_demand,
    cast(replace(nullif(sale_price_agreed_rede_demand, ''), ',', '') as double) as sale_price_agreed_rede_demand,
    cast(replace(nullif(brokerage_fee_rede_demand, ''), ',', '') as double) as brokerage_fee_rede_demand,
    cast(replace(nullif(brokerage_amount_rede_demand, ''), ',', '') as double) as brokerage_amount_rede_demand,
    cast(replace(nullif(partner_fee_value_demand_rede, ''), ',', '') as double) as partner_fee_value_demand_rede,
    cast(replace(nullif(brokerage_quinto_andar_amount_rede_demand, ''), ',', '') as double) as brokerage_quinto_andar_amount_rede_demand,
    cast(replace(nullif(brokerage_estate_agent_amount_rede_demand, ''), ',', '') as double) as brokerage_estate_agent_amount_rede_demand,
    cast(nullif(dt_legal_analysis_supply, '') as date) as dt_legal_analysis_supply,
    cast(replace(nullif(sale_price_agreed_rede_supply, ''), ',', '') as double) as sale_price_agreed_rede_supply,
    cast(replace(nullif(brokerage_fee_rede_supply, ''), ',', '') as double) as brokerage_fee_rede_supply,
    cast(replace(nullif(brokerage_amount_rede_supply, ''), ',', '') as double) as brokerage_amount_rede_supply,
    cast(replace(nullif(brokerage_quinto_andar_amount_rede_supply, ''), ',', '') as double) as brokerage_quinto_andar_amount_rede_supply,
    cast(replace(nullif(brokerage_estate_agent_amount_rede_supply, ''), ',', '') as double) as brokerage_estate_agent_amount_rede_supply
from
    datalake_gsheets_clean.recon_for_sale_sheets
)

,input_full_prep_1 as (
    select
        coalesce(q.id_offer, s.id_offer) as id_offer,
        q.id_house,
        q.dt_rescued,
        q.dt_cancelled as dt_cancelled_orig,
        q.dt_accounting_entry,
        q.dt_sale_agreement_signed,
        q.dt_payment_allowed,
        q.dt_legal_analysis_platform,
        q.dt_recon_platform,
        q.business_unit_description,
        q.payment_model,
        q.is_contract_amendment,
        q.is_legal_entity,
        q.cost_center_platform,
        q.location,
        q.supply_x_demand_platform,
        coalesce(q.sale_price_agreed_sales, 0) as sale_price_agreed_sales,
        coalesce(q.brokerage_fee_sales, 0) as brokerage_fee_sales,
        coalesce(q.sale_price_agreed_monopoly, 0) as sale_price_agreed_monopoly,
        coalesce(q.brokerage_fee_monopoly, 0) as brokerage_fee_monopoly,
        coalesce(q.sale_price_agreed_platform, 0) as sale_price_agreed_platform,
        coalesce(q.brokerage_amount_platform, 0) as brokerage_amount_platform,
        coalesce(q.brokerage_fee_platform, 0) as brokerage_fee_platform,
        coalesce(q.brokerage_quinto_andar_amount_platform, 0) as brokerage_quinto_andar_amount_platform,
        coalesce(q.brokerage_quinto_andar_fee, 0) as brokerage_quinto_andar_fee,
        coalesce(q.partner_fee_value_demand_platform, 0) as partner_fee_value_demand_platform,
        coalesce(q.brokerage_estate_agent_amount_platform, 0) as brokerage_estate_agent_amount_platform,
        coalesce(q.brokerage_estate_agent_fee, 0) as brokerage_estate_agent_fee,
        coalesce(q.total_received_platform, 0) as total_received_platform,
        coalesce(q.broker_payment_robin_hood, 0) as broker_payment_robin_hood,
        coalesce(q.broker_payment_accounting_entry, 0) as broker_payment_accounting_entry,
        coalesce(q.broker_payment_platform, 0) as broker_payment_platform,
        coalesce(q.broker_discount_platform, 0) as broker_discount_platform,
        coalesce(q.band_aid_cost, 0) as band_aid_cost,
        s.dt_reference_ledger,
        coalesce(s.invoice_amount_current_period, 0) as invoice_amount_current_period,
        coalesce(s.invoice_amount, 0) as invoice_amount,
        coalesce(s.rede_payment, 0) as rede_payment,
        coalesce(s.amount_indemnity_payment, 0) as amount_indemnity_payment,
        s.dt_legal_analysis_demand,
        coalesce(s.sale_price_agreed_rede_demand, 0) as sale_price_agreed_rede_demand,
        coalesce(s.brokerage_fee_rede_demand, 0) as brokerage_fee_rede_demand,
        coalesce(s.brokerage_amount_rede_demand, 0) as brokerage_amount_rede_demand,
        coalesce(s.partner_fee_value_demand_rede, 0) as partner_fee_value_demand_rede,
        coalesce(s.brokerage_quinto_andar_amount_rede_demand, 0) as brokerage_quinto_andar_amount_rede_demand,
        coalesce(s.brokerage_estate_agent_amount_rede_demand, 0) as brokerage_estate_agent_amount_rede_demand,
        s.dt_legal_analysis_supply,
        coalesce(s.sale_price_agreed_rede_supply, 0) as sale_price_agreed_rede_supply,
        coalesce(s.brokerage_fee_rede_supply, 0) as brokerage_fee_rede_supply,
        coalesce(s.brokerage_amount_rede_supply, 0) as brokerage_amount_rede_supply,
        coalesce(s.brokerage_quinto_andar_amount_rede_supply, 0) as brokerage_quinto_andar_amount_rede_supply,
        coalesce(s.brokerage_estate_agent_amount_rede_supply, 0) as brokerage_estate_agent_amount_rede_supply,
        coalesce(q.cancellation_brokerage, false) as cancellation_brokerage,
        coalesce(q.dt_legal_analysis_platform, s.dt_legal_analysis_supply, s.dt_legal_analysis_demand) as dt_legal_analysis,
        case 
            when coalesce(q.dt_rescued, date('1000-01-01')) < coalesce(q.dt_cancelled, date('1000-01-01'))
                then true 
            else false 
        end as offer_cancelled,
        case 
            when q.supply_x_demand_platform <> 'not_marketplace' 
                then q.supply_x_demand_platform
            when q.supply_x_demand_platform = 'not_marketplace' and coalesce(s.brokerage_amount_rede_demand, 0) <> 0 
                then 'demand'
            when q.supply_x_demand_platform = 'not_marketplace' and coalesce(s.partner_fee_value_demand_rede, 0) <> 0 
                then 'demand'
            when q.supply_x_demand_platform = 'not_marketplace' and coalesce(s.brokerage_amount_rede_supply, 0) <> 0 
                then 'supply'
            else 'not_marketplace'
        end as supply_x_demand
    from 
    input_platform q
    full outer join 
    input_gsheets s 
        on q.id_offer = s.id_offer
)

,input_full_prep_2 as (
select
    *
    ,case 
        when coalesce(dt_rescued, date('1000-01-01')) < coalesce(dt_cancelled_orig, date('1000-01-01')) 
            then dt_cancelled_orig
        else null 
    end as dt_cancelled,
    case 
        when supply_x_demand = 'demand' then '002S4X'
        when supply_x_demand = 'supply' then '002S3X'
        else '002S2X'
    end as cost_center,
    greatest(
        coalesce(cast(dt_cancelled_orig as date), date('1000-01-01')),
        coalesce(cast(dt_legal_analysis as date), date('1000-01-01')),
        coalesce(cast(dt_reference_ledger as date), date('1000-01-01')),
        coalesce(cast(dt_accounting_entry as date), date('1000-01-01'))
    ) as dt_recon
from 
input_full_prep_1
)

,input_treatment_payment as (
    select
        *,
        (rede_payment + amount_indemnity_payment) as broker_payment_rede_ti,
        (broker_payment_platform + rede_payment + amount_indemnity_payment) as broker_payment
    from 
    input_full_prep_2
)

,input_classification_treatment_rede as (
    select
        *,
        case
            when supply_x_demand = 'demand'
                and supply_x_demand_platform = 'not_marketplace'
                and brokerage_amount_rede_demand <> 0
                and (abs(broker_payment) + abs(total_received_platform) + abs(invoice_amount) <> 0)
                and round(
                        abs(broker_payment - brokerage_estate_agent_amount_rede_demand) +
                        abs(invoice_amount - brokerage_quinto_andar_amount_rede_demand) +
                        abs(total_received_platform - brokerage_amount_rede_demand)
                    , 2) 
                    < 
                    round(
                        abs(broker_payment - brokerage_estate_agent_amount_platform) +
                        abs(invoice_amount - brokerage_quinto_andar_amount_platform) +
                        abs(total_received_platform - brokerage_amount_platform)
                    , 2)
            then 'REDE_DEMAND'
            when supply_x_demand = 'supply'
                and supply_x_demand_platform = 'not_marketplace'
                and brokerage_amount_rede_supply <> 0
                and brokerage_quinto_andar_amount_rede_supply <> 0
                and brokerage_estate_agent_amount_rede_supply <> 0
                and (abs(broker_payment) + abs(total_received_platform) + abs(invoice_amount) <> 0)
                and round(
                        abs(broker_payment - brokerage_estate_agent_amount_rede_supply) +
                        abs(invoice_amount - brokerage_quinto_andar_amount_rede_supply) +
                        abs(total_received_platform - brokerage_amount_rede_supply)
                    , 2) 
                    < 
                    round(
                        abs(broker_payment - brokerage_estate_agent_amount_platform) +
                        abs(invoice_amount - brokerage_quinto_andar_amount_platform) +
                        abs(total_received_platform - brokerage_amount_platform)
                    , 2)
            then 'REDE_SUPPLY'
            else 'PLATFORM'
        end as classification_treatment_rede_recon
    from 
    input_treatment_payment
)

,input_brokerage_treatment_rede as (
    select
        *,
        case
            when classification_treatment_rede_recon = 'REDE_SUPPLY' then brokerage_amount_rede_supply
            when classification_treatment_rede_recon = 'REDE_DEMAND' then brokerage_amount_rede_demand
            else brokerage_amount_platform
        end as brokerage_amount,

        case
            when classification_treatment_rede_recon = 'REDE_SUPPLY' then brokerage_estate_agent_amount_rede_supply
            when classification_treatment_rede_recon = 'REDE_DEMAND' then brokerage_estate_agent_amount_rede_demand
            else brokerage_estate_agent_amount_platform
        end as brokerage_estate_agent_amount,

        case
            when classification_treatment_rede_recon = 'REDE_SUPPLY' then brokerage_quinto_andar_amount_rede_supply
            when classification_treatment_rede_recon = 'REDE_DEMAND' then brokerage_quinto_andar_amount_rede_demand
            else brokerage_quinto_andar_amount_platform
        end as brokerage_quinto_andar_amount,

        case
            when classification_treatment_rede_recon = 'REDE_SUPPLY' then sale_price_agreed_rede_supply
            when classification_treatment_rede_recon = 'REDE_DEMAND' then sale_price_agreed_rede_demand
            else sale_price_agreed_platform
        end as sale_price_agreed,

        case
            when classification_treatment_rede_recon = 'REDE_SUPPLY' then brokerage_fee_rede_supply
            when classification_treatment_rede_recon = 'REDE_DEMAND' then brokerage_fee_rede_demand
            else brokerage_fee_platform
        end as brokerage_fee,

        case
            when classification_treatment_rede_recon = 'REDE_DEMAND' then partner_fee_value_demand_rede
            else partner_fee_value_demand_platform
        end as partner_fee_value_demand
    from 
    input_classification_treatment_rede
)

,input_negative_payment_classification as (
select
    * except(broker_payment)
    ,case
        when classification_treatment_discount_recon = 'WITH_TREATMENT' then 0
        else broker_discount_platform
    end as broker_discount
    ,case
        when classification_treatment_broker_payment_recon = 'WITH_TREATMENT' then 0
        else broker_payment
    end as broker_payment
from(
        select
            *,
            case
                when (broker_payment + broker_discount_platform) < 0 then 'WITH_TREATMENT'
                else 'WITHOUT_TREATMENT'
            end as classification_treatment_discount_recon,

            case
                when broker_payment < 0 then 'WITH_TREATMENT'
                else 'WITHOUT_TREATMENT'
            end as classification_treatment_broker_payment_recon
        from 
        input_brokerage_treatment_rede
    )
)

,input_negative_received_treatment as (
    select
        *,
        case
            when total_received_platform < 0 then 'WITH_TREATMENT'
            else 'WITHOUT_TREATMENT'
        end as classification_treatment_negative_received_recon,
        case
            when total_received_platform < 0 then 0
            else total_received_platform
        end as total_received
    from 
        input_negative_payment_classification
)

,input_classification_cash_flow as (
    select
        *,
        case
            when abs((broker_payment + invoice_amount) - total_received) <= 0.05
                and ((broker_payment + invoice_amount) <> 0 and invoice_amount <> 0 and total_received <> 0)
                and (
                        round(broker_payment, 2) <> round(brokerage_estate_agent_amount, 2) or
                        round(invoice_amount, 2) <> round(brokerage_quinto_andar_amount, 2) or
                        round(total_received, 2) <> round(brokerage_amount, 2)
                    )
                and (sale_price_agreed_monopoly <= sale_price_agreed_sales)
            then 'WITH_TREATMENT'
            else 'WITHOUT_TREATMENT'
        end as classification_treatment_cash_flow_x_brokerage_recon
    from 
        input_negative_received_treatment
)

,input_brokerage_cash_flow_override as (
    select
        * except(brokerage_estate_agent_amount, brokerage_quinto_andar_amount, brokerage_amount),

        case
            when classification_treatment_cash_flow_x_brokerage_recon = 'WITH_TREATMENT' then broker_payment
            else brokerage_estate_agent_amount
        end as brokerage_estate_agent_amount,

        case
            when classification_treatment_cash_flow_x_brokerage_recon = 'WITH_TREATMENT' then invoice_amount
            else brokerage_quinto_andar_amount
        end as brokerage_quinto_andar_amount,

        case
            when classification_treatment_cash_flow_x_brokerage_recon = 'WITH_TREATMENT' then total_received
            else brokerage_amount
        end as brokerage_amount
    from 
        input_classification_cash_flow
),

input_partner_fee_and_sale_price as (
    select
        * except(partner_fee_value_demand, sale_price_agreed),

        case
            when classification_treatment_cash_flow_x_brokerage_recon = 'WITH_TREATMENT' 
                and supply_x_demand <> 'not_marketplace'
            then (sale_price_agreed * brokerage_fee) - brokerage_amount
            else partner_fee_value_demand
        end as partner_fee_value_demand,

        case
            when classification_treatment_cash_flow_x_brokerage_recon = 'WITH_TREATMENT' 
                and supply_x_demand = 'not_marketplace'
            then brokerage_amount / nullif(brokerage_fee, 0)
            else sale_price_agreed
        end as sale_price_agreed
    from 
        input_brokerage_cash_flow_override
),

input_gross_brokerage as (
    select
        *,
        (sale_price_agreed * brokerage_fee) as gross_brokerage_amount
    from 
        input_partner_fee_and_sale_price
)

select
    id_offer,
    id_house,
    dt_recon_platform,
    dt_legal_analysis_platform,
    dt_cancelled,
    dt_rescued,
    dt_accounting_entry,
    dt_sale_agreement_signed,
    dt_payment_allowed,
    business_unit_description,
    payment_model,
    is_contract_amendment,
    is_legal_entity,
    cost_center_platform,
    location,
    supply_x_demand_platform,
    cancellation_brokerage,
    offer_cancelled,
    sale_price_agreed_sales,
    brokerage_fee_sales,
    sale_price_agreed_monopoly,
    brokerage_fee_monopoly,
    sale_price_agreed_platform,
    brokerage_amount_platform,
    brokerage_fee_platform,
    brokerage_quinto_andar_amount_platform,
    brokerage_quinto_andar_fee,
    partner_fee_value_demand_platform,
    brokerage_estate_agent_amount_platform,
    brokerage_estate_agent_fee,
    total_received_platform,
    broker_payment_robin_hood,
    broker_payment_accounting_entry,
    broker_payment_platform,
    broker_discount_platform,
    band_aid_cost,
    dt_reference_ledger,
    rede_payment,
    amount_indemnity_payment,
    dt_legal_analysis_demand,
    sale_price_agreed_rede_demand,
    brokerage_fee_rede_demand,
    brokerage_amount_rede_demand,
    partner_fee_value_demand_rede,
    brokerage_quinto_andar_amount_rede_demand,
    brokerage_estate_agent_amount_rede_demand,
    dt_legal_analysis_supply,
    sale_price_agreed_rede_supply,
    brokerage_fee_rede_supply,
    brokerage_amount_rede_supply,
    brokerage_quinto_andar_amount_rede_supply,
    brokerage_estate_agent_amount_rede_supply,
    dt_legal_analysis,
    supply_x_demand,
    cost_center,
    invoice_amount_current_period,
    invoice_amount,
    dt_recon,
    broker_payment_rede_ti,
    broker_payment,
    classification_treatment_rede_recon,
    brokerage_amount,
    brokerage_estate_agent_amount,
    brokerage_quinto_andar_amount,
    sale_price_agreed,
    brokerage_fee,
    partner_fee_value_demand,
    classification_treatment_discount_recon,
    classification_treatment_broker_payment_recon,
    broker_discount,
    classification_treatment_negative_received_recon,
    total_received,
    classification_treatment_cash_flow_x_brokerage_recon,
    gross_brokerage_amount
from 
    input_gross_brokerage
where 
    true
    and cast(dt_recon as date) between cast('2025-01-01' as date) and last_day(add_months(current_date, -1))
