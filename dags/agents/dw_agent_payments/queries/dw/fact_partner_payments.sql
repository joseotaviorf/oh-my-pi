WITH base AS (
    SELECT
        ae.id_partner_payment,
        ae.id_earning,
        ae.id_earning_source,
        ae.id_revenue_share,
        ae.id_house,
        ae.id_contract,
        ae.id_offer,
        ae.id_business_unit,
        ae.id_tier,
        ae.id_user,
        ae.uuid_person,
        ae.uuid_company,
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
        ae.ts_created,
        ae.ts_updated
    FROM
        datalake_agent_payments.partner_payments AS ae
    WHERE
        DATE(ae.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
ts_created_window AS (
    SELECT
        MIN(DATE(ts_created)) AS min_dt,
        MAX(DATE(ts_created)) AS max_dt
    FROM
        base
),
agent_hub_ranked AS (
    SELECT
        mha.uuid_person,
        mha.id_parent_member_profile,
        mha.dt_reference,
        ROW_NUMBER() OVER (
            PARTITION BY
                mha.uuid_person,
                mha.dt_reference
            ORDER BY
                IF(mha.id_parent_member_profile IS NOT NULL, 0, 1)
        ) AS rn
    FROM
        datalake_hub_services.member_hub_allocation AS mha
    CROSS JOIN
        ts_created_window AS w
    WHERE
        mha.profile = 'AGENT'
        AND mha.business_context = 'SALE'
        AND mha.is_active = TRUE
        AND mha.uuid_person IS NOT NULL
        AND MAKE_DATE(mha.year, mha.month, mha.day) BETWEEN w.min_dt AND w.max_dt
),
agent_hub AS (
    SELECT
        uuid_person,
        id_parent_member_profile,
        dt_reference
    FROM
        agent_hub_ranked
    WHERE
        rn = 1
),
negotiation_executives AS (
    SELECT
        mha.id_member_profile,
        mha.id_main_user AS id_main_user_en,
        mha.dt_reference
    FROM
        datalake_hub_services.member_hub_allocation AS mha
    CROSS JOIN
        ts_created_window AS w
    WHERE
        mha.profile = 'NEGOTIATION_EXECUTIVE'
        AND mha.is_active = TRUE
        AND MAKE_DATE(mha.year, mha.month, mha.day) BETWEEN w.min_dt AND w.max_dt
),
associated_executives_ranked AS (
    SELECT
        mha.id_business_unit,
        mha.id_main_user AS id_main_user_ea,
        mha.dt_reference,
        ROW_NUMBER() OVER (
            PARTITION BY
                mha.id_business_unit,
                mha.dt_reference
            ORDER BY
                mha.id_main_user
        ) AS rn
    FROM
        datalake_hub_services.member_hub_allocation AS mha
    CROSS JOIN
        ts_created_window AS w
    WHERE
        mha.profile = 'ASSOCIATED_EXECUTIVE'
        AND mha.is_active = TRUE
        AND MAKE_DATE(mha.year, mha.month, mha.day) BETWEEN w.min_dt AND w.max_dt
),
associated_executives AS (
    SELECT
        id_business_unit,
        id_main_user_ea,
        dt_reference
    FROM
        associated_executives_ranked
    WHERE
        rn = 1
)
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
    CASE
        WHEN ae.is_fifty_revenue_share THEN COALESCE(os.id_user_fifty_agent, -1)
        ELSE -1
    END AS sk_user_fifty_agent,
    COALESCE(en.id_main_user_en, -1) AS sk_negotiation_executive,
    COALESCE(ea.id_main_user_ea, -1) AS sk_associated_executive,
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
    ae.ts_created,
    ae.ts_updated,
    NOW() AS ts_load,
    YEAR(ae.ts_created) AS year,
    MONTH(ae.ts_created) AS month,
    DAY(ae.ts_created) AS day
FROM
    base AS ae
LEFT JOIN
    datalake_person.person_sks AS person
        ON ae.uuid_person = person.uuid_person
LEFT JOIN
    datalake_company.company_sks AS company
        ON ae.uuid_company = company.uuid_company
LEFT JOIN
    core_brokers.brokers AS cb
        ON ae.uuid_company = cb.uuid_company
LEFT JOIN
    datalake_sale_offer_flows.offer_specialists AS os
        ON ae.id_offer = os.id_offer
LEFT JOIN
    agent_hub
        ON agent_hub.uuid_person = ae.uuid_person
        AND agent_hub.dt_reference = DATE(ae.ts_created)
        AND ae.business_context = 'SALE'
LEFT JOIN
    negotiation_executives AS en
        ON en.id_member_profile = agent_hub.id_parent_member_profile
        AND en.dt_reference = agent_hub.dt_reference
LEFT JOIN
    associated_executives AS ea
        ON ea.id_business_unit = ae.id_business_unit
        AND ea.dt_reference = DATE(ae.ts_created)
        AND ae.business_context = 'SALE'
