SELECT
    ae.id_partner_payment AS sk_partner_payment,
    ae.id_earning AS sk_earning,
    ae.id_earning_source AS sk_earning_source,
    ae.id_revenue_share AS sk_revenue_share,
    ae.id_house AS sk_house,
    ae.id_contract AS sk_contract,
    ae.id_offer AS sk_offer,
    ae.id_business_unit AS sk_business_unit,
    ae.id_tier AS sk_tier,
    ae.id_user AS sk_user,
    person.sk_person,
    company.sk_company,
    COALESCE(cb.sk_broker, -1) AS sk_broker,
    ae.incentive_system,
    ae.business_context,
    ae.participant_role,
    ae.tier_name,
    ae.revenue_receiver_type,
    ae.revenue_source,
    ae.revenue_role,
    ae.revenue_share_type,
    ae.revenue_share_value,
    ae.ticket_base_amount,
    ae.brokerage_fee,
    ae.brokerage_amount,
    ae.revenue_amount,
    ae.revenue_percentage,
    ae.is_3p_lead_gen_offer,
    ae.is_fifty_revenue_share,
    ae.is_crcc_revenue_share,
    ae.is_tier_revenue_share,
    ae.dt_tier_reference,
    ae.ts_contract_signed,
    ae.ts_created,
    ae.ts_updated,
    NOW() AS ts_load,
    YEAR(ae.ts_created) AS year,
    MONTH(ae.ts_created) AS month,
    DAY(ae.ts_created) AS day
FROM
    datalake_agent_payments.partner_payments AS ae
LEFT JOIN
    datalake_person.person_sks AS person
        ON ae.uuid_person = person.uuid_person
LEFT JOIN
    datalake_company.company_sks AS company
        ON ae.uuid_company = company.uuid_company
LEFT JOIN
    core_brokers.brokers AS cb
        ON ae.uuid_company = cb.uuid_company
WHERE
    DATE(ae.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')