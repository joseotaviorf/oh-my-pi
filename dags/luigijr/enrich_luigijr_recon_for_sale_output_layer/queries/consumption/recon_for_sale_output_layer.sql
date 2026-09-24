-- Databricks notebook source

with 

input_layer as (
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
    ops_fintech.recon_for_sale_input_layer
)

,output_broker_asset_liabilies as (
select
    *,
    case
        when (
            ((offer_cancelled = true and cancellation_brokerage = true) or offer_cancelled = false)
            and broker_payment < brokerage_estate_agent_amount
            and abs(brokerage_estate_agent_amount - (broker_payment + broker_discount)) < 20
        )
        then -broker_discount
        when (
            ((offer_cancelled = true and cancellation_brokerage = true) or offer_cancelled = false)
            and broker_payment < brokerage_estate_agent_amount
            and abs(brokerage_estate_agent_amount - (broker_payment + broker_discount)) >= 20
            and total_received > brokerage_amount
            and (broker_payment + broker_discount) > brokerage_estate_agent_amount
        )
        then 0
        when (
            ((offer_cancelled = true and cancellation_brokerage = true) or offer_cancelled = false)
            and broker_payment < brokerage_estate_agent_amount
            and abs(brokerage_estate_agent_amount - (broker_payment + broker_discount)) >= 20
            and total_received > brokerage_amount
            and (broker_payment + broker_discount) <= brokerage_estate_agent_amount
        )
        then -(brokerage_estate_agent_amount - (broker_payment + broker_discount))
        when (
            ((offer_cancelled = true and cancellation_brokerage = true) or offer_cancelled = false)
            and broker_payment < brokerage_estate_agent_amount
            and abs(brokerage_estate_agent_amount - (broker_payment + broker_discount)) >= 20
            and total_received <= brokerage_amount
            and (broker_payment + broker_discount) > brokerage_estate_agent_amount
        )
        then -(brokerage_estate_agent_amount * (total_received / nullif(brokerage_amount, 0)) - brokerage_estate_agent_amount)
        when (
            ((offer_cancelled = true and cancellation_brokerage = true) or offer_cancelled = false)
            and broker_payment < brokerage_estate_agent_amount
            and abs(brokerage_estate_agent_amount - (broker_payment + broker_discount)) >= 20
            and total_received <= brokerage_amount
            and (broker_payment + broker_discount) <= brokerage_estate_agent_amount
        )
        then -(brokerage_estate_agent_amount * (total_received / nullif(brokerage_amount, 0)) - (broker_payment + broker_discount))
        else -broker_discount
    end as broker_asset_x_liabilities
from input_layer
)

,output_accounting_band_aid as (
    select
        *,
        -band_aid_cost as accounting_band_aid_cost
    from output_broker_asset_liabilies
)

,output_accounting_receivables as (
select
    *,
    case
        when invoice_amount <> 0 
            and offer_cancelled = false 
            and coalesce(
            (
                least(brokerage_quinto_andar_amount, invoice_amount) - 
                ((total_received / nullif(brokerage_amount, 0)) * brokerage_quinto_andar_amount)
            ),  0) > 0
        then coalesce(
            (
                least(brokerage_quinto_andar_amount, invoice_amount) - 
                ((total_received / nullif(brokerage_amount, 0)) * brokerage_quinto_andar_amount)
            ) + ((brokerage_quinto_andar_amount / nullif(brokerage_amount, 0)) * accounting_band_aid_cost),
            0
        )
        else 0
    end as accounting_receivables
from output_accounting_band_aid
)

,output_accounting_brokerage_provision as (
    select
        *,
        case
            when brokerage_quinto_andar_amount > invoice_amount
                and offer_cancelled = false
                and dt_legal_analysis is not null
            then brokerage_quinto_andar_amount - invoice_amount
            when (total_received * brokerage_quinto_andar_amount / nullif(brokerage_amount, 0)) > invoice_amount
                and offer_cancelled = true
                and cancellation_brokerage = true
            then (total_received * brokerage_quinto_andar_amount / nullif(brokerage_amount, 0)) - invoice_amount
            else 0
        end as accounting_brokerage_provision
    from output_accounting_receivables
)

,output_accounting_cancellation_receivables as (
    select
        *,
        case
            when offer_cancelled = true
                and cancellation_brokerage = true
                and invoice_amount <> 0
                and (total_received = 0 or brokerage_amount > total_received)
            then coalesce(
                ((brokerage_amount - total_received) * brokerage_quinto_andar_amount) / nullif(brokerage_amount, 0),
                0
            )
            else 0
        end as accounting_cancellation_receivables
    from output_accounting_brokerage_provision
)

,output_accounting_advance_broker_payment as (
    select
        *,
        case
            when broker_discount < 0 then -1 * broker_discount
            else 0
        end as accounting_advance_broker_payment
    from output_accounting_cancellation_receivables
)

,output_accounting_buyer_amount_to_transfer as (
    select
        *,
        case
            when offer_cancelled = true and cancellation_brokerage = false then
                case
                    when total_received >= 0 then -total_received
                    else 0
                end
            else
                case
                    when total_received > brokerage_amount then -(total_received - brokerage_amount)
                    else 0
                end
        end as accounting_buyer_amount_to_transfer
    from output_accounting_advance_broker_payment
)

,output_accounting_advance_buyer_payment as (
    select
        *,
        case
            when invoice_amount = 0 then
                -coalesce(
                    (total_received + accounting_buyer_amount_to_transfer) * (brokerage_quinto_andar_amount / nullif(brokerage_amount, 0)),
                    0
                )
            when invoice_amount <> 0 
                and brokerage_amount > invoice_amount 
                and coalesce(((total_received + accounting_buyer_amount_to_transfer) * (brokerage_quinto_andar_amount / nullif(brokerage_amount, 0))) - invoice_amount, 0) < 0 
            then 0
            when invoice_amount <> 0 
                and brokerage_amount > invoice_amount 
                and coalesce(((total_received + accounting_buyer_amount_to_transfer) * (brokerage_quinto_andar_amount / nullif(brokerage_amount, 0))) - invoice_amount, 0) >= 0 
            then -coalesce(((total_received + accounting_buyer_amount_to_transfer) * (brokerage_quinto_andar_amount / nullif(brokerage_amount, 0))) - invoice_amount, 0)
            else 0
        end as accounting_advance_buyer_payment
    from output_accounting_buyer_amount_to_transfer
)

,output_accounting_broker_amount_to_transfer as (
    select
        *,
        case
            when broker_asset_x_liabilities < 0 then broker_asset_x_liabilities
            else 0
        end as accounting_broker_amount_to_transfer
    from output_accounting_advance_buyer_payment
)

,output_accounting_brokerage_revenue as (
    -- CTE para accounting_brokerage_revenue
    select
        *,
        -invoice_amount_current_period as accounting_brokerage_revenue
    from output_accounting_broker_amount_to_transfer
),

output_accounting_cancellation_revenue_current_period as (
    select
        *,
        case
            when offer_cancelled = true and cancellation_brokerage = false 
                then invoice_amount
            else 0
        end as accounting_cancellation_revenue_current_period
    from output_accounting_brokerage_revenue
)

,output_accounting_cancellation_revenue_previous_period as (
    select
        *,
        case
            when offer_cancelled = true 
                and cancellation_brokerage = false 
                and dt_cancelled < trunc(last_day(add_months(current_date(), -1)), 'YEAR')
                then invoice_amount
            else 0
        end as accounting_cancellation_revenue_previous_period
    from output_accounting_cancellation_revenue_current_period
)

,output_accounting_cancellation_revenue as (
    select
        *,
        (accounting_cancellation_revenue_current_period - accounting_cancellation_revenue_previous_period) as accounting_cancellation_revenue
    from output_accounting_cancellation_revenue_previous_period
)

,output_loss_adjust_invoice_current_period as (
    select
        *,
        case
            when invoice_amount > brokerage_quinto_andar_amount
                and invoice_amount <> 0
                and offer_cancelled = false
            then invoice_amount - brokerage_quinto_andar_amount

            when invoice_amount <= brokerage_quinto_andar_amount
                and invoice_amount <> 0
            then invoice_amount - brokerage_quinto_andar_amount + accounting_brokerage_provision

            else 0
        end as loss_adjust_invoice_current_period
    from output_accounting_cancellation_revenue
)

,output_loss_adjust_invoice_previous_period as (
    select
        *,
        case
            when dt_reference_ledger < trunc(last_day(add_months(current_date(), -1)), 'YEAR')
            then loss_adjust_invoice_current_period
            else 0
        end as loss_adjust_invoice_previous_period
    from output_loss_adjust_invoice_current_period
)

,output_loss_overpayment_current_period as (
    select
        *,
        case
            when offer_cancelled = false or (offer_cancelled = true and cancellation_brokerage = true)
            then greatest(
                (broker_payment - accounting_broker_amount_to_transfer) - 
                (brokerage_estate_agent_amount * ((total_received + accounting_buyer_amount_to_transfer) / nullif(brokerage_amount, 0))) - 
                accounting_advance_broker_payment,
                0
            )
            else (broker_payment - accounting_broker_amount_to_transfer - accounting_advance_broker_payment)
        end as loss_overpayment_current_period
    from output_loss_adjust_invoice_previous_period
)

,output_adjust_underpayment_current_period as (
    select
        *,
        case
            when (offer_cancelled = false or (offer_cancelled = true and cancellation_brokerage = true))
                and coalesce(
                    (broker_payment - accounting_broker_amount_to_transfer) - 
                    (brokerage_estate_agent_amount * (least(total_received, brokerage_amount) / nullif(brokerage_amount, 0))), 
                    0
                ) < 0
            then coalesce(
                (broker_payment - accounting_broker_amount_to_transfer) - 
                (brokerage_estate_agent_amount * (least(total_received, brokerage_amount) / nullif(brokerage_amount, 0))), 
                0
            )
            else 0
        end as adjust_underpayment_current_period
    from output_loss_overpayment_current_period
)

,output_loss_overpayment_previous_period as (
    select
        *,
        case
            when dt_accounting_entry < trunc(last_day(add_months(current_date(), -1)), 'YEAR')
            then loss_overpayment_current_period
            else 0
        end as loss_overpayment_previous_period
    from output_adjust_underpayment_current_period
)

,output_adjust_underpayment_previous_period as (
    select
        *,
        case
            when dt_accounting_entry < trunc(last_day(add_months(current_date(), -1)), 'YEAR')
            then adjust_underpayment_current_period
            else 0
        end as adjust_underpayment_previous_period
    from output_loss_overpayment_previous_period
)

,output_loss_adjust_invoice as (
    select
        *,
        (loss_adjust_invoice_current_period - loss_adjust_invoice_previous_period) as loss_adjust_invoice
    from output_adjust_underpayment_previous_period
)

,output_loss_overpayment as (
    select
        *,
        (loss_overpayment_current_period - loss_overpayment_previous_period) as loss_overpayment
    from output_loss_adjust_invoice
)

,output_adjust_underpayment as (
    select
        *,
        (adjust_underpayment_current_period - adjust_underpayment_previous_period) as adjust_underpayment
    from output_loss_overpayment
)

,output_accounting_total_loss_previous_period as (
    select
        *,
        (adjust_underpayment_previous_period + loss_overpayment_previous_period + loss_adjust_invoice_previous_period) as accounting_total_loss_previous_period
    from output_adjust_underpayment
)

,output_accounting_total_loss as (
    select
        *,
        (loss_adjust_invoice + loss_overpayment + adjust_underpayment) as accounting_total_loss
    from output_accounting_total_loss_previous_period
)

,output_accounting_balance as (
    select
        *,
        (
            abs(accounting_receivables) +
            abs(accounting_brokerage_provision) +
            abs(accounting_cancellation_receivables) +
            abs(accounting_advance_broker_payment) +
            abs(accounting_advance_buyer_payment) +
            abs(accounting_buyer_amount_to_transfer) +
            abs(accounting_broker_amount_to_transfer) +
            abs(accounting_brokerage_revenue) +
            abs(accounting_cancellation_revenue) +
            abs(accounting_total_loss) +
            abs(accounting_band_aid_cost)
        ) as accounting_balance
    from output_accounting_total_loss
)

,output_classification_completeness as (
    select
        *,
        case
            when cast(dt_recon as date) >= cast('2026-04-01' as date)
                then 'balance_with_movement'
            when round(accounting_balance, 2) > 0.01 
                then 'balance_without_movement'
            else 'no_balance'
        end as classification_completeness
    from output_accounting_balance
)

select
    id_offer,
    id_house,
    business_unit_description,
    payment_model,
    sale_price_agreed,
    brokerage_fee,
    dt_sale_agreement_signed,
    dt_accounting_entry,
    dt_reference_ledger,
    dt_legal_analysis,
    dt_cancelled,
    offer_cancelled,
    cancellation_brokerage,
    dt_payment_allowed,
    supply_x_demand,
    location,
    cost_center,
    is_legal_entity,
    is_contract_amendment,
    gross_brokerage_amount,
    partner_fee_value_demand,
    brokerage_amount,
    brokerage_quinto_andar_amount,
    brokerage_estate_agent_amount,
    total_received,
    broker_payment,
    broker_discount,
    invoice_amount_current_period,
    invoice_amount,
    band_aid_cost,
    broker_payment_platform,
    broker_payment_rede_ti,
    accounting_receivables,
    accounting_brokerage_provision,
    accounting_cancellation_receivables,
    accounting_advance_broker_payment,
    accounting_advance_buyer_payment,
    accounting_buyer_amount_to_transfer,
    accounting_broker_amount_to_transfer,
    accounting_brokerage_revenue,
    accounting_cancellation_revenue,
    accounting_total_loss,
    accounting_band_aid_cost,
    loss_adjust_invoice_current_period,
    accounting_cancellation_revenue_previous_period,
    accounting_total_loss_previous_period,
    loss_adjust_invoice_previous_period,
    loss_overpayment_previous_period,
    adjust_underpayment_previous_period  
from 
    output_classification_completeness
where 
    classification_completeness = 'balance_with_movement'

-- COMMAND ----------
