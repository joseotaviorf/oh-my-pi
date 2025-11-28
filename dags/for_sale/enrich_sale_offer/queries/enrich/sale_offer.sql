WITH users_base AS (
    SELECT
        so.id_offer,
        u_by.id_external AS u_by_id_buyer,
        u_sl.id_external AS u_sl_id_seller,
        u_by.id_house AS u_by_id_house,
        so.*
    FROM
        datalake_sale_offer_flows.sale_offer_flows AS so
    JOIN
        datalake_sale_offer_flows.sale_offer_users AS u_by
            ON so.id_offer = u_by.id_firestore
            AND u_by.type = 'BUYER'
    JOIN
        datalake_sale_offer_flows.sale_offer_users AS u_sl
            ON so.id_offer = u_sl.id_firestore
            AND u_sl.type = 'SELLER'
    WHERE
        u_by.is_original_user = TRUE
        AND u_sl.is_original_user = TRUE
),

-- RELATION BOOKING OFFER - Vendas
visit_before_offer AS (
    SELECT
        so.id_offer,
        bs.id AS id_booking,
        bs.id_agent,
        so.id_house,
        du.id AS id_user_agent,
        bs.id_company_supply,
        bs.id_company_demand,
        bs.partner_3p_supply,
        bs.partner_3p_demand,
        bs.is_3p_supply,
        bs.is_3p_demand,
        bs.is_3p_lead_gen,
        bs.has_3p_access_control,
        TRUE AS flg_visit_completed_before_offer,
        (UNIX_TIMESTAMP(so.ts_created) - UNIX_TIMESTAMP(bs.ts_booking_utc))/(3600) AS hours_visit_to_offer,
        so.ts_offer_created
    FROM
        users_base AS so
    JOIN
        datalake_booking.booking AS bs
            ON bs.id_house = so.id_house
            AND bs.id_visitor = so.u_by_id_buyer
    LEFT JOIN
        datalake_ebdb_user.user AS du
            ON bs.id_agent = du.id_agent
    WHERE
        bs.visit_intent = 'SALE'
        AND bs.type = 'Visita'
        AND bs.ts_booking_utc < so.ts_offer_created
        AND bs.visit_fup ='VaiNegociar'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY so.id_offer ORDER BY (UNIX_TIMESTAMP(so.ts_offer_created) - UNIX_TIMESTAMP(bs.ts_booking_utc))) = 1
),
booking_before_offer AS (
    SELECT
        so.id_offer,
        bs.id AS id_booking,
        bs.id_agent,
        du.id AS id_user_agent,
        bs.id_company_supply,
        bs.id_company_demand,
        bs.partner_3p_supply,
        bs.partner_3p_demand,
        bs.is_3p_supply,
        bs.is_3p_demand,
        bs.is_3p_lead_gen,
        bs.has_3p_access_control,
        TRUE AS flg_booking_before_offer,
        (UNIX_TIMESTAMP(so.ts_offer_created) - UNIX_TIMESTAMP(bs.ts_created))/(3600) AS hours_booking_to_offer,
        so.ts_offer_created
    FROM
        users_base AS so
    JOIN
        datalake_booking.booking AS bs
            ON bs.id_house = so.id_house
            AND bs.id_visitor = so.u_by_id_buyer
    LEFT JOIN
        datalake_ebdb_user.user AS du
            ON bs.id_agent = du.id_agent
    WHERE
        bs.visit_intent = 'SALE'
        AND bs.type = 'Visita'
        AND bs.ts_created < so.ts_offer_created
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY so.id_offer ORDER BY is_canceled, (UNIX_TIMESTAMP(so.ts_offer_created) - UNIX_TIMESTAMP(bs.ts_created))) = 1
),
relation_booking_offer AS (
    SELECT
        COALESCE(vo.id_offer, bo.id_offer) AS id_offer,
        COALESCE(vo.id_booking, bo.id_booking) AS id_booking,
        COALESCE(vo.id_agent, bo.id_agent) AS id_agent,
        COALESCE(vo.id_user_agent, bo.id_user_agent) AS id_user_agent,
        COALESCE(vo.id_company_supply, bo.id_company_supply) AS id_company_supply,
        COALESCE(vo.id_company_demand, bo.id_company_demand) AS id_company_demand,
        COALESCE(vo.partner_3p_supply, bo.partner_3p_supply) AS partner_3p_supply,
        COALESCE(vo.partner_3p_demand, bo.partner_3p_demand) AS partner_3p_demand,
        COALESCE(vo.is_3p_supply, bo.is_3p_supply) AS is_3p_supply,
        COALESCE(vo.is_3p_demand, bo.is_3p_demand) AS is_3p_demand,
        COALESCE(vo.is_3p_lead_gen, bo.is_3p_lead_gen) AS is_3p_lead_gen,
        COALESCE(vo.has_3p_access_control, bo.has_3p_access_control) AS has_3p_access_control,
        COALESCE(vo.hours_visit_to_offer, bo.hours_booking_to_offer) AS hours_booking_to_offer,
        COALESCE(bo.flg_booking_before_offer, vo.flg_visit_completed_before_offer) AS flg_booking_before_offer,
        vo.flg_visit_completed_before_offer,
        COALESCE(vo.ts_offer_created, bo.ts_offer_created) AS ts_offer_created
    FROM
        visit_before_offer AS vo
    FULL OUTER JOIN
        booking_before_offer AS bo
            ON bo.id_offer = vo.id_offer
),
-- REGIONS - Vendas
sale_listings AS (
    SELECT
        DISTINCT sl.id_house,
        h.id_user AS id_owner,
        h.id_region
    FROM
        datalake_sale_listings.sale_listing AS sl
    JOIN
        datalake_ebdb_clean.house AS h
            ON sl.id_house = h.id
),
regions_base AS (
    SELECT
        so.id_offer,
        so.id_house,
        sl.id_region,
        so.u_sl_id_seller AS id_owner,
        r.city_group
    FROM
        users_base AS so
    LEFT JOIN
        sale_listings AS sl
            ON sl.id_house = so.id_house
    LEFT JOIN
        datalake_region.region AS r
            ON r.id = sl.id_region
),

-- WORK CONTRACT
work_contract_base AS (
    SELECT
        ac.id_agent,
        ac.id_user_agent,
        wc.id_hub_teams,
        wc.hub_name_teams,
        ac.previous_work_contract_name,
        ac.work_contract_name AS contract_name,
        ac.ts_work_contract_started AS ts_work_contract_start,
        COALESCE(ac.ts_work_contract_ended, CURRENT_DATE) AS ts_work_contract_end
    FROM
        datalake_ebdb_agents.agent_contract AS ac
    LEFT JOIN
        datalake_ebdb_work_contract.work_contract AS wc
            ON ac.id_work_contract = wc.id
),
work_contract AS (
    SELECT
        vo.id_offer,
        wc.id_agent,
        wc.id_user_agent,
        wc.id_hub_teams,
        wc.contract_name AS agent_work_contract,
        wc.hub_name_teams,
        wc.ts_work_contract_start,
        wc.ts_work_contract_end
    FROM
        relation_booking_offer AS rbo
    LEFT JOIN
        datalake_sale_offer_flows.sale_offer_flows AS vo
            ON rbo.id_offer = vo.id_offer
    LEFT JOIN
        work_contract_base AS wc
            ON rbo.id_user_agent = wc.id_user_agent
            AND vo.ts_offer_created BETWEEN wc.ts_work_contract_start AND wc.ts_work_contract_end
),
sale_offer_status AS (
    SELECT
        id_sales_flow,
        id_firestore,
        primary_closing_type_label,
        secundary_closing_type_label,
        macro_status_name,
        ordering,
        last_micro_status_name,
        ts_macro_status_start,
        ts_macro_status_end,
        ts_micro_status_last_update
    FROM
        datalake_sale_offer_flows.sale_offer_status
),
data_from_sales_flow AS (
    SELECT
        vo.id_offer,
        vo.id_sales_flow,
        vo.id_buyer,
        vo.id_house,
        vo.id_seller,
        IF(vo.id_consultant IS NOT NULL, vo.id_consultant, NULL) AS id_consultant,
        vo.id_user_consultant,
        IF(vo.sk_team_lead IS NOT NULL, vo.sk_team_lead, NULL) AS id_team_lead,
        vo.sk_user_team_lead AS id_user_team_lead,
        vo.id_pendency,
        vo.id_user_agent,
        vo.id_agent,
        ebdb_user.id_agent AS ebdb_id_agent,
        vo.id_hub,
        vo.vendas_offer_flow,
        vo.sale_agreement_cancellation_reason,
        vo.payment_method,
        vo.payment_model,
        vo.payment_status,
        vo.credit_status,
        vo.house_dilligence_status,
        vo.seller_dilligence_status,
        vo.report_dilligence_status,
        vo.vendas_offer_status AS offer_status,
        vo.sale_agreement_status,
        vo.credit_model,
        vo.financing_bank,
        vo.drop_reason,
        vo.drop_reason_responsible,
        vo.fgts_value,
        vo.sale_listing_price,
        vo.entry_amount AS earnest_value,
        vo.first_price_offered_by_buyer,
        vo.last_price_offered_by_buyer,
        vo.first_discount_proposed,
        vo.last_discount_proposed,
        vo.sale_price_agreed,
        vo.brokerage_fee,
        vo.is_ccv_5a_model,
        vo.is_ccv_canceled,
        vo.is_a_rescued_ccv,
        vo.is_a_rescued_offer,
        vo.days_sale_agreement_created_to_sale_agreement_signed,
        vo.days_offer_accepted_to_sale_agreement_signed,
        vo.days_offer_accepted_to_sale_agreement_created,
        vo.days_offer_accepted_to_offer_dismissed,
        DATE(vo.ts_accepted) AS dt_offer_accepted,
        DATE(ts_discarded) AS dt_offer_dismissed,
        vo.dt_offer_rescued,
        vo.dt_sale_agreement_created,
        DATE(vo.ts_signed) AS dt_sale_agreement_signed,
        vo.dt_sale_transacton_paid,
        vo.dt_sale_agreement_cancelled,
        vo.dt_sale_agreement_rescued,
        vo.ts_offer_created
    FROM
        users_base AS vo
    LEFT JOIN
        datalake_ebdb_user.user AS ebdb_user
            ON vo.id_user_agent = ebdb_user.id
            AND vo.id_user_agent IS NOT NULL
),
-- BUSINESS UNIT
business_unit_by_hub_id(
    SELECT
        bu.id AS id_hub,
        bu.hub_name,
        bu.business_context
    FROM
        datalake_hub_services_clean.business_unit AS bu
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY bu.id ORDER BY bu.ts_updated DESC) = 1
)
SELECT
    v.id_offer AS id_offer,
    v.id_sales_flow AS id_sales_flow,
    rbo.id_booking,
    v.id_buyer AS id_buyer,
    COALESCE(v.id_seller, r.id_owner) AS id_owner,
    v.id_house AS id_house,
    COALESCE(v.id_user_agent, rbo.id_user_agent) AS id_user_agent,
    COALESCE(v.ebdb_id_agent, rbo.id_agent) AS id_agent,
    v.id_hub,
    v.id_consultant AS id_consultant,
    CAST(v.id_user_consultant AS BIGINT) AS id_user_consultant,
    v.id_user_consultant AS id_closing_specialist,
    v.id_team_lead,
    v.id_user_team_lead,
    v.id_pendency,
    COALESCE(wc_off.id_hub_teams, busf.id_hub) AS id_business_unit,
    r.id_region,
    rbo.id_company_supply,
    rbo.id_company_demand,
    h.uuid_company AS uuid_company_supply,
    UPPER(
        CASE
            WHEN v.vendas_offer_flow = 'CENTRAL' AND r.city_group = 'Porto Alegre' THEN 'CENTRAL POA'
            WHEN v.vendas_offer_flow = 'CENTRAL' AND r.city_group = 'RMSP' THEN 'CENTRAL SP'
            WHEN v.vendas_offer_flow = 'CENTRAL' AND r.city_group = 'Rio de Janeiro' THEN 'CENTRAL RJ'
            WHEN v.vendas_offer_flow = 'CENTRAL' THEN 'CENTRAL NO INFO'
            WHEN v.vendas_offer_flow = 'HUB' THEN COALESCE(wc_off.hub_name_teams, busf.hub_name)
            ELSE v.vendas_offer_flow
        END
    ) AS business_unit,
    v.vendas_offer_flow,
    rbo.partner_3p_supply,
    rbo.partner_3p_demand,
    rbo.is_3p_supply,
    rbo.is_3p_demand,
    rbo.is_3p_lead_gen,
    rbo.has_3p_access_control,
    rbo.flg_booking_before_offer,
    rbo.flg_visit_completed_before_offer,
    v.sale_agreement_cancellation_reason AS sale_agreement_cancellation_reason,
    v.drop_reason AS drop_reason,
    CASE
        WHEN LOWER(v.drop_reason_responsible) LIKE '%buyer%'
            THEN 'Buyer'
        WHEN LOWER(v.drop_reason_responsible) LIKE '%seller%'
            THEN 'Seller'
        ELSE 'Other'
    END AS drop_reason_responsible,
    v.fgts_value AS fgts_value,
    sr.financed_amount AS financing_value,
    COALESCE(v.earnest_value, sr.entry_payment_amount) AS earnest_value,
    v.brokerage_fee,
    v.sale_listing_price AS sale_price,
    v.first_price_offered_by_buyer AS first_price_offered_by_buyer,
    v.last_price_offered_by_buyer AS last_price_offered_by_buyer,
    v.first_discount_proposed AS first_discount_proposed,
    v.last_discount_proposed AS last_discount_proposed,
    v.sale_price_agreed AS sale_price_agreed,
    CASE
        WHEN v.is_ccv_5a_model IS True THEN "Default 5A CCV"
        WHEN v.is_ccv_5a_model IS False THEN "Not a 5A CCV Model"
        ELSE "Unknown"
    END AS ccv_type,
    v.payment_status,
    v.credit_status,
    v.offer_status,
    v.sale_agreement_status,
    v.payment_model,
    v.credit_model,
    v.financing_bank,
    r.city_group,
    v.house_dilligence_status,
    v.seller_dilligence_status,
    v.report_dilligence_status,
    IF(
        MIN(v.ts_offer_created) OVER (PARTITION BY v.id_offer ORDER BY v.ts_offer_created) = v.ts_offer_created,
        TRUE,
        FALSE
    ) AS is_buyer_first_offer,
    IF(
        MIN(v.ts_offer_created) OVER (PARTITION BY v.id_house ORDER BY v.ts_offer_created) = v.ts_offer_created,
        TRUE,
        FALSE
    ) AS is_house_first_offer,
    COALESCE(h.is_3p_supply_5a, FALSE) AS is_3p_supply_5a,
    COALESCE(h.is_3p_supply_bh, FALSE) AS is_3p_supply_bh,
    v.is_ccv_canceled AS is_ccv_canceled,
    v.is_a_rescued_ccv,
    v.is_a_rescued_offer,
    v.days_sale_agreement_created_to_sale_agreement_signed,
    v.days_offer_accepted_to_sale_agreement_signed,
    v.days_offer_accepted_to_sale_agreement_created,
    v.days_offer_accepted_to_offer_dismissed,
    CASE
        WHEN v.dt_offer_accepted IS NOT NULL
            THEN DATEDIFF(DATE(v.dt_offer_accepted), DATE(v.ts_offer_created))
        ELSE NULL
    END AS days_offer_submitted_to_offer_accepted,
    CASE
        WHEN v.dt_sale_agreement_created IS NOT NULL
            THEN DATEDIFF(DATE(v.dt_sale_agreement_created), DATE(v.ts_offer_created))
        ELSE NULL
    END AS days_offer_submitted_to_sale_agreement_created,
    CASE
        WHEN v.dt_offer_dismissed IS NOT NULL
            THEN DATEDIFF(DATE(v.dt_offer_dismissed), DATE(v.ts_offer_created))
        ELSE NULL
    END AS days_offer_submitted_to_offer_dismissed,
    CASE
        WHEN v.dt_sale_agreement_signed IS NOT NULL
            THEN DATEDIFF(DATE(v.dt_sale_agreement_signed), DATE(v.ts_offer_created))
        ELSE NULL
    END AS days_offer_submitted_to_sale_agreement_signed,
    rbo.hours_booking_to_offer,
    v.dt_offer_accepted AS dt_offer_accepted,
    v.dt_offer_dismissed AS dt_offer_dismissed,
    v.dt_offer_rescued,
    v.dt_sale_agreement_created,
    v.dt_sale_agreement_signed AS dt_sale_agreement_signed,
    v.dt_sale_transacton_paid AS dt_sale_transacton_paid,
    v.dt_sale_agreement_cancelled AS dt_sale_agreement_cancelled,
    v.dt_sale_agreement_rescued,
    DATE(v.ts_offer_created) AS dt_offer_created,
    v.ts_offer_created AS ts_offer_submitted,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    data_from_sales_flow AS v
LEFT JOIN
    datalake_monopoly_clean.sale_revision AS sr
        ON v.id_offer = sr.id_external_offer
LEFT JOIN
    relation_booking_offer AS rbo
        ON rbo.id_offer = v.id_offer
LEFT JOIN
    regions_base AS r
        ON v.id_offer = r.id_offer
LEFT JOIN
    business_unit_by_hub_id AS busf
        ON v.id_hub = busf.id_hub
        AND v.id_hub IS NOT NULL
LEFT JOIN
    datalake_ebdb_listing.house AS h
        ON v.id_house = h.id
LEFT JOIN
    work_contract AS wc_off
        ON v.id_offer = wc_off.id_offer
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY v.id_offer ORDER BY revision DESC) = 1