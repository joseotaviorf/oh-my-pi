-- RELATION BOOKING OFFER
 WITH 
    first_booking_author AS (
        SELECT DISTINCT
            bsc.id_booking,
            FIRST_VALUE(id_user) OVER (
            PARTITION BY bsc.id_booking ORDER BY id
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ) AS id_user_creation
        FROM
            datalake_ebdb_clean.booking_status_change AS bsc
    ),
    agent_contract_aud AS (
        SELECT
            adaud.id AS id_agent,
            adaud.rev,
            adaud.id_work_contract,
            CAST(FROM_UNIXTIME(ure.ts_revision/1000) AS TIMESTAMP) + (ure.ts_revision % 1000) * INTERVAL 1 MILLISECONDS AS ts_revision,
            LAG(adaud.id_work_contract) OVER (PARTITION BY adaud.id ORDER BY adaud.rev) AS previous_id_work_contract
        FROM
            datalake_ebdb_clean.agent_data_aud AS adaud
        LEFT JOIN
            datalake_ebdb_clean.user_revision_entity AS ure
                ON ure.id = adaud.rev
        WHERE
            adaud.id_work_contract IS NOT NULL
    ),
    agent_contract AS (
        SELECT
            id_agent,
            id_work_contract,
            ts_revision AS ts_work_contract_start,
            LEAD(ts_revision) OVER (PARTITION BY id_agent ORDER BY rev) AS ts_work_contract_end
        FROM
            agent_contract_aud
        WHERE
            previous_id_work_contract <> id_work_contract
            OR previous_id_work_contract IS NULL
    ),
    booking_3p_demand_agent AS (
        SELECT
            b.id,
            wc.id_company_hubspot AS id_company_demand,
            wc.3p_partner AS partner_3p_demand
        FROM
            agent_contract AS ac
        JOIN
            datalake_ebdb_clean.booking AS b
                ON b.ts_created BETWEEN ac.ts_work_contract_start AND COALESCE(ac.ts_work_contract_end, CURRENT_TIMESTAMP)
                AND ac.id_agent = b.id_agent
        JOIN
            datalake_ebdb_work_contract.work_contract AS wc
                ON wc.id = ac.id_work_contract
        WHERE
            is_3p_contract
    ),
    base_booking AS (
      SELECT
        b.id,
        b.id_house,
        b.id_visitor,
        b.id_agent,
        su.id_user_5a AS id_user_sale_attendence_5a,
        b3pa.id_company_demand,
        b3pa.partner_3p_demand,
        b.visit_fup,
        IF(b3pa.id IS NOT NULL, TRUE, FALSE) AS is_3p_demand,
        (b.status = 'Cancelado') AS is_canceled,
        CAST(b.dt_booking AS TIMESTAMP)
          + FLOOR((b.slot_day * 15 / 60)+8) * INTERVAL 1 HOURS
          + ABS(b.slot_day * 15 % 60) * INTERVAL 1 MINUTES
        AS ts_booking_local_tz,
        TO_UTC_TIMESTAMP(CAST(b.dt_booking AS TIMESTAMP)
          + FLOOR((b.slot_day * 15 / 60)+8) * INTERVAL 1 HOURS
          + ABS(b.slot_day * 15 % 60) * INTERVAL 1 MINUTES, ct.default_timezone) AS ts_booking_utc,
        b.ts_created
      FROM
        datalake_ebdb_clean.booking AS b
      LEFT JOIN
          first_booking_author AS fba
              ON fba.id_booking = b.id 
      LEFT JOIN
          datalake_hub_services.secretariat_hierarchy AS su
              ON su.id_user_5a = fba.id_user_creation
      LEFT JOIN
          booking_3p_demand_agent AS b3pa
              ON b3pa.id = b.id
      LEFT JOIN
        datalake_ebdb_listing.house AS hl
            ON b.id_house = hl.id
      LEFT JOIN
          datalake_ebdb_clean.country AS ct
              ON ct.code = hl.country_code                                
      WHERE
          b.business_context = 'SALE'
          AND b.type = 'Visita'
    ),
  visit_before_offer AS (
    WITH vc_aux AS (
        SELECT
            COALESCE(g.id, vo.id_offer) AS id_offer,
            bs.id AS id_booking,
            bs.id_agent,
            bs.id_user_sale_attendence_5a AS id_user_secretariat_booking_creator,
            du.id AS id_user_agent,
            bs.id_company_demand,
            du.name AS agent_name,
            bs.partner_3p_demand,
            bs.is_3p_demand,
            TRUE AS flg_visit_completed_before_offer,
            (unix_timestamp(COALESCE(g.ts_created, vo.ts_offer_created))-unix_timestamp(bs.ts_created))/(3600) AS hours_booking_to_offer,
            (unix_timestamp(COALESCE(g.ts_created, vo.ts_offer_created))-unix_timestamp(bs.ts_booking_utc))/(3600) AS hours_visit_to_offer,
            ROW_NUMBER() OVER (
                PARTITION BY
                    COALESCE(g.id, vo.id_offer)
                ORDER BY
                    (unix_timestamp(COALESCE(g.ts_created, vo.ts_offer_created))-unix_timestamp(bs.ts_booking_utc))
            ) AS rw_visit_completed,
            bs.ts_created AS ts_booking_created
        FROM
            datalake_firestore.sale_offer AS g
        FULL OUTER JOIN
            datalake_sale_offer_flows.sale_offer_flows AS vo
                    ON vo.id_offer = g.id
        JOIN
            base_booking AS bs
                ON bs.id_house = COALESCE(vo.id_house, g.id_house)
                AND bs.id_visitor = COALESCE(vo.id_buyer, g.id_buyer)
        LEFT JOIN
            datalake_ebdb_user.user AS du
                ON bs.id_agent = du.id_agent
        WHERE
            bs.ts_booking_utc < COALESCE(vo.ts_offer_created, g.ts_created)
            AND bs.visit_fup ='VaiNegociar'
    )
    SELECT
        vc.*
    FROM
        vc_aux AS vc
    WHERE
        vc.rw_visit_completed = 1
),
booking_before_offer AS (
    WITH bk_aux AS (
        SELECT
            COALESCE(vo.id_offer, g.id) AS id_offer,
            bs.id AS id_booking,
            bs.id_agent,
            bs.id_user_sale_attendence_5a AS id_user_secretariat_booking_creator,
            du.id AS id_user_agent,
            bs.id_company_demand,
            du.name AS agent_name,
            bs.partner_3p_demand,
            bs.is_3p_demand,
            TRUE AS flg_booking_before_offer,
            (unix_timestamp(COALESCE(vo.ts_offer_created, g.ts_created))-unix_timestamp(bs.ts_created))/(3600) AS hours_booking_to_offer,
            (unix_timestamp(COALESCE(vo.ts_offer_created, g.ts_created))-unix_timestamp(bs.ts_booking_utc))/(3600) AS hours_visit_to_offer,
            ROW_NUMBER() OVER (
                PARTITION BY
                    COALESCE(vo.id_offer ,g.id)
                ORDER BY
                    is_canceled,
                    (unix_timestamp(COALESCE( vo.ts_offer_created, g.ts_created))-unix_timestamp(bs.ts_created))
            ) AS rw_booking,
            bs.ts_created AS ts_booking_created
        FROM
            datalake_firestore.sale_offer AS g
        FULL OUTER JOIN
            datalake_sale_offer_flows.sale_offer_flows AS vo
                    ON vo.id_offer = g.id
        JOIN
            base_booking AS bs
                ON bs.id_house = COALESCE(vo.id_house, g.id_house)
                AND bs.id_visitor = COALESCE(vo.id_buyer, g.id_buyer)
        LEFT JOIN
            datalake_ebdb_user.user AS du
                ON bs.id_agent = du.id_agent
        WHERE
           bs.ts_created < COALESCE(vo.ts_offer_created, g.ts_created)
    )
    SELECT
        bk.*
    FROM
        bk_aux AS bk
    WHERE
        rw_booking = 1
),
relation_booking_offer AS (
    SELECT
        COALESCE(vo.id_offer, bo.id_offer) AS id_offer,
        COALESCE(vo.id_booking, bo.id_booking) AS id_booking,
        COALESCE(vo.id_agent, bo.id_agent) AS id_agent,
        CASE 
            WHEN vo.id_booking IS NOT NULL THEN vo.id_user_secretariat_booking_creator
            ELSE bo.id_user_secretariat_booking_creator
        END AS id_user_secretariat_booking_creator,
        COALESCE(vo.id_user_agent, bo.id_user_agent) AS id_user_agent,
        CASE
            WHEN vo.is_3p_demand IS NOT NULL THEN vo.id_company_demand
            ELSE bo.id_company_demand
        END AS id_company_demand,
        COALESCE(vo.agent_name, bo.agent_name) AS agent_name,
        CASE
            WHEN vo.is_3p_demand IS NOT NULL THEN vo.partner_3p_demand
            ELSE bo.partner_3p_demand
        END AS partner_3p_demand,
        COALESCE(vo.hours_booking_to_offer, bo.hours_booking_to_offer) AS hours_booking_to_offer,
        COALESCE(vo.hours_visit_to_offer, bo.hours_visit_to_offer) AS hours_visit_to_offer,
        COALESCE(vo.is_3p_demand, bo.is_3p_demand) AS is_3p_demand,
        COALESCE(bo.flg_booking_before_offer,vo.flg_visit_completed_before_offer) AS flg_booking_before_offer,
        vo.flg_visit_completed_before_offer,
        COALESCE(vo.ts_booking_created, bo.ts_booking_created) AS ts_booking_created
    FROM
        visit_before_offer AS vo
    FULL OUTER JOIN
        booking_before_offer AS bo
            ON bo.id_offer = vo.id_offer
),
-- WORK CONTRACT
work_contract AS (
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
-- REGIONS
regions AS (
    WITH giroffer_regions AS (
        SELECT
            COALESCE(vo.id_offer, g.id) AS id_offer,
            COALESCE(vo.id_buyer, g.id_buyer) AS id_buyer,
            COALESCE(vo.id_house, g.id_house) AS id_house,
            COALESCE(vo.id_seller, g.id_owner) AS id_owner,
            COALESCE(vo.ts_offer_created, g.ts_created) AS ts_offer_created,
            COALESCE(vo.last_price_offered_by_buyer, g.last_price_offered_by_buyer) AS last_price_offered_by_buyer
        FROM
            datalake_firestore.sale_offer AS g
        FULL OUTER JOIN
            datalake_sale_offer_flows.sale_offer_flows AS vo
                ON vo.id_offer = g.id
    ),
    aux_sale_listings AS (
        SELECT
            sl.id_house AS sk_house,
            h.id_user AS sk_owner,
            h.id_region AS sk_region
        FROM
            datalake_sale_listings.sale_listing AS sl
        JOIN
            datalake_ebdb_clean.house AS h
                ON sl.id_house = h.id
              ),
    aux AS (
        SELECT
            coalesce(g.id_offer, ohc.id_offer) AS id_offer,
            coalesce(g.id_house, ohc.id_house_5a) AS id_house,
            coalesce(fl_girofer.sk_region, fl_ohc.sk_region) AS id_region,
            coalesce(g.id_owner, fl_ohc.sk_owner) AS id_owner
        FROM
            giroffer_regions AS g
        FULL OUTER JOIN
            datalake_gsheets_clean.offers_hub_central AS ohc
                ON ohc.id_offer = g.id_offer
        LEFT JOIN (
            SELECT
                DISTINCT sk_house,
                sk_region,
                sk_owner
            FROM
                aux_sale_listings
            ) AS fl_ohc
                ON fl_ohc.sk_house = ohc.id_house_5a
        LEFT JOIN (
            SELECT
                DISTINCT sk_house,
                sk_region,
                sk_owner
            FROM
                aux_sale_listings
            ) AS fl_girofer
                ON fl_girofer.sk_house = g.id_house
        GROUP BY
            1,
            2,
            3,
            4
    )
    SELECT
        aux.*,
        dr.city_group
    FROM
        aux
    LEFT JOIN
        datalake_region.region AS dr
            ON dr.id = aux.id_region
),
aux_monday_users AS (
    SELECT
        us.id,
        gmu.*,
        ROW_NUMBER() OVER (PARTITION BY gmu.id_monday ORDER BY user_name) AS row
    FROM
        datalake_gsheets_clean.monday_users AS gmu
    LEFT JOIN
        datalake_ebdb_user.user AS us
            ON gmu.user_email = us.email
),
-- DATA SOURCES
data_sources AS (
    SELECT
        -- data from giroffer
        COALESCE(vo.id_offer, g.id) AS id_offer,
        COALESCE(vo.id_buyer, g.id_buyer) AS id_buyer,
        COALESCE(vo.id_house, g.id_house) AS id_house,
        COALESCE(vo.id_seller, g.id_owner) AS id_owner,
        COALESCE(vo.ts_offer_created, g.ts_created) AS ts_offer_created,
        COALESCE(vo.sale_listing_price, g.sale_price) AS sale_price,
        COALESCE(vo.first_price_offered_by_buyer, g.first_price_offered_by_buyer) AS first_price_offered_by_buyer,
        COALESCE(vo.last_price_offered_by_buyer, g.last_price_offered_by_buyer) AS last_price_offered_by_buyer,
        COALESCE(vo.ts_offer_updated, g.ts_updated) AS ts_updated,
        COALESCE(vo.has_used_fgts_in_payment, g.has_used_fgts_in_payment) AS has_used_fgts_in_payment,
        COALESCE(vo.has_used_negotiation_chat, g.has_used_negotiation_chat) AS has_used_negotiation_chat,
        COALESCE(vo.last_discount_proposed, g.last_discount_proposed) AS last_discount_proposed,
        COALESCE(vo.first_discount_proposed, g.first_discount_proposed) AS first_discount_proposed,
        COALESCE(vo.payment_method, g.current_payment_method) AS current_payment_method,
        COALESCE(vo.planned_payment_method, g.planned_payment_method) AS planned_payment_method,
        COALESCE(vo.registry_price, g.registry_price) AS registry_price,
        COALESCE(vo.itbi_price, g.itbi_price) AS itbi_price,
        COALESCE(vo.entry_amount, g.payment_entry_amount) AS payment_entry_amount,
        COALESCE(vo.financing_value, g.financing_value) AS financing_value,
        COALESCE(vo.fgts_value, g.fgts_value) AS fgts_value,
        COALESCE(vo.down_payment_value, g.earnest_value) AS earnest_value,
        COALESCE(vo.brokerage_fee, g.brokerage_fee) AS giroffer_brokerage_fee,
        COALESCE(vo.id_sale_flow, g.id_sale_flow) AS id_sale_flow,
        -- data from relation_booking_offer
        rbo.id_user_agent AS rbo_id_user_agent,
        rbo.id_booking,
        rbo.id_company_demand,
        rbo.id_user_secretariat_booking_creator,
        UPPER(rbo.agent_name) AS rbo_agent_name,
        rbo.partner_3p_demand,
        COALESCE(rbo.is_3p_demand, FALSE) AS is_3p_demand,
        COALESCE(rbo.flg_booking_before_offer,FALSE) AS flg_booking_before_offer,
        COALESCE(rbo.flg_visit_completed_before_offer,FALSE) AS flg_visit_completed_before_offer,
        rbo.hours_booking_to_offer,
        rbo.hours_visit_to_offer,
        rbo.ts_booking_created,
        -- data from gsheets
        ohc.id_offer AS ohc_id_offer,
        ohc.id_buyer AS ohc_id_buyer,
        ohc.id_house AS ohc_id_house,
        ohc.status AS ohc_status,
        ohc.offer_model AS ohc_offer_model,
        -- data from work_contract
        wc.id_agent AS wc_id_agent,
        wc.id_hub_teams,
        wc.contract_name AS agent_work_contract,
        CASE
            WHEN wc.contract_name LIKE '%HUB%'
                THEN 'HUB'
            WHEN wc.contract_name LIKE '%CENTRAL%'
                THEN 'CENTRAL'
            ELSE 'DEAL_MAKING'
        END AS wc_offer_flow,
        wc.hub_name_teams,
        -- data from gsheets_offer_hub_central
        ohc.ohc_offer_flow,
        ohc.ohc_offer_flow_detail,
        ohc.executive AS ohc_consultant_name,
        ohc.executive_lead AS ohc_team_lead_name,
        ohc.sale_price_agreed AS ohc_sale_price_agreed,
        ohc.dt_offer_submitted as ohc_offer_submitted_date,
        ohc.dt_offer_accepted as ohc_offer_accepted_date,
        ohc.dt_offer_dismissed as ohc_offer_dismissed_date,
        ohc.dt_sale_agreement_signed as ohc_sale_agreement_signed_date,
        --data from vendas
        vo.id_offer AS vo_id_offer,
        vo.vendas_offer_status,
        vo.brokerage_fee AS vo_brokerage_fee,
        vo.flow_step AS vo_flow_step,
        vo.id_sales_flow AS id_vendas,
        vo.ts_accepted AS vo_offer_accepted_date,
        vo.ts_discarded AS vo_offer_dismissed_date,
        vo.ts_signed AS vo_sale_agreement_signed_date,
        vo.id_user_consultant AS vo_id_user_consultant,
        vo.id_pendency,
        vo.sale_price_agreed AS vo_sale_price_agreed,
        vo.id_user_agent AS vo_id_user_agent,
        vo.id_agent AS vo_id_agent,
        du_vo.id_agent AS du_vo_id_agent,
        vo.id_hub,
        vo.agent_name AS vo_agent_name,
        vo.pendency,
        vo.pendency_type,
        vo.opportunities_of_the_week,
        vo.vendas_offer_flow,
        vo.consultant_name AS vo_consultant_name,
        vo.team_lead_name AS vo_team_lead_name,
        vo.financing_bank AS vo_financing_bank,
        vo.sale_agreement_status AS vo_sale_agreement_status,
        vo.sale_agreement_cancellation_reason AS vo_sale_agreement_cancellation_reason,
        vo.drop_reason AS vo_drop_reason,
        vo.drop_reason_responsible AS vo_drop_reason_responsible,
        vo.diligence_appointment_reason AS vo_diligence_appointment_reason,
        vo.credit_model AS vo_credit_model,
        vo.closing_status AS vo_closing_status,
        vo.house_dilligence_status AS vo_house_dilligence_status,
        vo.seller_dilligence_status AS vo_seller_dilligence_status,
        vo.report_dilligence_status AS vo_report_dilligence_status,
        vo.bank_analysis_status AS vo_bank_analysis_status,
        vo.payment_model AS vo_payment_model,
        vo.payment_status AS vo_payment_status,
        vo.payment_method AS vo_payment_method,
        vo.credit_status AS vo_credit_status,
        vo.notary_office_status AS vo_notary_office_status,
        vo.real_estate_register_office_status AS vo_real_estate_register_office_status,
        vo.tags_from_salesflow AS vo_tags_from_salesflow,
        vo.has_seller_debt_payments AS vo_has_seller_debt_payments,
        vo.is_ccv_canceled AS vo_is_ccv_canceled,
        vo.is_a_rescued_ccv AS vo_is_a_rescued_ccv,
        vo.is_a_rescued_offer AS vo_is_a_rescued_offer,
        vo.is_ccv_5a_model AS vo_is_ccv_5a_model,
        vo.dt_sale_agreement_rescued AS vo_dt_sale_agreement_rescued,
        vo.dt_offer_rescued AS vo_dt_offer_rescued,
        vo.ts_last_updated_pendency AS vo_ts_last_updated_pendency,
        vo.dt_sale_transacton_paid AS vo_dt_sale_transacton_paid,
        vo.dt_house_registry_ended AS vo_dt_house_registry_ended,
        vo.dt_house_registry_started AS vo_dt_house_registry_started,
        vo.dt_sale_agreement_cancelled AS vo_dt_sale_agreement_cancelled,
        vo.dt_sale_agreement_created AS vo_dt_sale_agreement_created,
        vo.days_sale_agreement_created_to_sale_agreement_signed AS vo_days_sale_agreement_created_to_sale_agreement_signed,
        vo.days_offer_accepted_to_sale_agreement_signed AS vo_days_offer_accepted_to_sale_agreement_signed,
        vo.days_offer_accepted_to_sale_agreement_created AS vo_days_offer_accepted_to_sale_agreement_created,
        vo.days_offer_accepted_to_offer_dismissed AS vo_days_offer_accepted_to_offer_dismissed,
        CASE
            WHEN vo.id_consultant IS NOT NULL
                THEN 'ID_vendas_' || vo.id_consultant
            END AS vo_id_consultant,
        CASE
            WHEN vo.sk_team_lead IS NOT NULL
                THEN 'ID_vendas_' || vo.sk_team_lead
            END AS vo_sk_team_lead,
        vo.sk_user_team_lead AS vo_id_user_team_lead,
        vo.ts_seller_fup AS vo_ts_seller_fup,
        vo.ts_buyer_fup AS vo_ts_buyer_fup,
        -- data from monday
        mo.id_offer AS mo_id_offer,
        mo.offer_status AS monday_offer_status,
        mo.status AS monday_status,
        mo.dt_accepted AS mo_offer_accepted_date,
        mo.dt_offer_dismissed AS mo_offer_dismissed_date,
        mo.dt_sale_agreement_signed AS mo_sale_agreement_signed_date,
        mo.id_closing_specialist AS mo_id_closing_specialist,
        mo.sale_price_agreed AS mo_sale_price_agreed,
        mo.price_offered_by_buyer AS mo_price_offered_by_buyer,
        mo.financing_bank AS mo_financing_bank,
        mo.sale_agreement_status AS mo_sale_agreement_status,
        mo.sale_agreement_cancellation_reason AS mo_sale_agreement_cancellation_reason,
        mo.drop_reason AS mo_drop_reason,
        mo.drop_reason_responsible AS mo_drop_reason_responsible,
        mo.diligence_appointment_reason AS mo_diligence_appointment_reason,
        mo.offer_acceptance_probability AS offer_acceptance_probability,
        mo.credit_model AS mo_credit_model,
        mo.closing_status AS mo_closing_status,
        mo.house_dilligence_status AS mo_house_dilligence_status,
        mo.seller_dilligence_status AS mo_seller_dilligence_status,
        mo.report_dilligence_status AS mo_report_dilligence_status,
        mo.bank_analysis_status AS mo_bank_analysis_status,
        mo.payment_status AS mo_payment_status,
        mo.payment_model AS mo_payment_model,
        mo.credit_status AS mo_credit_status,
        mo.notary_office_status AS mo_notary_office_status,
        vo.notary_office_details AS vo_notary_office_details,
        mo.real_estate_register_office_status AS mo_real_estate_register_office_status,
        mo.early_keys_status AS mo_early_keys_status,
        mo.tags_from_salesflow as mo_tags_from_salesflow,
        mo.has_seller_debt_payments AS mo_has_seller_debt_payments,
        mo.is_ccv_canceled AS mo_is_ccv_canceled,
        mo.dt_sale_transacton_paid AS mo_dt_sale_transacton_paid,
        mo.dt_house_registry_ended AS mo_dt_house_registry_ended,
        mo.dt_house_registry_started AS mo_dt_house_registry_started,
        mo.dt_sale_agreement_cancelled AS mo_dt_sale_agreement_cancelled,
        mo.dt_sale_agreement_created AS mo_dt_sale_agreement_created,
        mo.days_sale_agreement_created_to_sale_agreement_signed AS mo_days_sale_agreement_created_to_sale_agreement_signed,
        mo.days_offer_accepted_to_sale_agreement_signed AS mo_days_offer_accepted_to_sale_agreement_signed,
        mo.days_offer_accepted_to_sale_agreement_created AS mo_days_offer_accepted_to_sale_agreement_created,
        mo.days_offer_accepted_to_offer_dismissed AS mo_days_offer_accepted_to_offer_dismissed,
        amu.id AS mo_id_user_consultant,
        amu.user_name AS mo_consultant_name,
        CASE
            WHEN mo.id_consultant IS NOT NULL
                THEN 'ID_MONDAY_' || mo.id_consultant
        END AS mo_id_consultant
    FROM
        datalake_firestore.sale_offer AS g
    FULL OUTER JOIN
        datalake_sale_offer_flows.sale_offer_flows AS vo
            ON vo.id_offer = g.id
    LEFT JOIN
        relation_booking_offer AS rbo
            ON rbo.id_offer = COALESCE(vo.id_offer, g.id)
    FULL OUTER JOIN
        datalake_gsheets.sale_hub_offer AS ohc
            ON ohc.id_offer = COALESCE(vo.id_offer, g.id)
    LEFT JOIN
        datalake_ebdb_user.user AS du_vo
            ON vo.id_user_agent = du_vo.id
            AND vo.id_user_agent IS NOT NULL
    LEFT JOIN
        datalake_firestore.monday AS mo
            ON mo.id_offer = COALESCE(vo.id_offer, g.id)
    LEFT JOIN
        work_contract AS wc
            ON wc.id_user_agent = rbo.id_user_agent
            AND COALESCE(vo.ts_offer_created, g.ts_created) >= wc.ts_work_contract_start
            AND (
                (COALESCE(vo.ts_offer_created, g.ts_created) <= wc.ts_work_contract_end)
                OR (wc.ts_work_contract_end IS NULL)
            )
    LEFT JOIN
        aux_monday_users AS amu
            ON amu.id_monday = REPLACE(
                REPLACE(
                    REVERSE(SPLIT(mo.id_consultant, ',')) [0],
                    '[',
                    ''
                ),
                ']',
                ''
            )
            AND amu.row = 1
),
-- OFFER FLOW CTE
offer_flow AS (
    SELECT
        id_offer,
        ohc_id_offer,
        ohc_offer_flow_detail,
        vo_id_offer,
        id_hub,
        id_hub_teams,
        hub_name_teams,
        CASE
            WHEN ds.ohc_offer_flow IS NOT NULL
                THEN ds.ohc_offer_flow -- Offers que estão na planilha de trabalho
            WHEN mo_id_consultant IS NOT NULL
                THEN 'DEAL_MAKING' -- Offers que tem deal maker associado
            WHEN ds.vendas_offer_flow = 'DEAL_MAKING'
                THEN 'DEAL_MAKING' -- Offers que não estão na planilha de trabalho e o Vendas diz ser DM
            WHEN ds.mo_id_offer IS NOT NULL
                AND COALESCE(ds.vo_id_offer,ds.ohc_id_offer) IS NULL
                    THEN 'DEAL_MAKING' -- Offers que não estão na planiha de trabalho e estão apenas no monday
            ELSE COALESCE(ds.vendas_offer_flow,'NOT DEFINED') -- Offers que não estão na planilha de trabalho, não foram atribuidas a um deal maker e possuem offer_flows diferentes de DM no Vendas.
        END AS offer_flow
    FROM
        data_sources AS ds
),
-- BUSINESS UNIT
business_unit_by_hub_id(
    SELECT
        off.id_hub,
        bu.hub_name,
        bu.business_context,
        ROW_NUMBER () OVER ( PARTITION BY bu.id ORDER BY bu.ts_updated DESC ) AS row
    FROM
        offer_flow AS off
    JOIN
        datalake_hub_services_clean.business_unit AS bu
            ON off.id_hub = bu.id
),

business_unit AS (
  SELECT
        off.id_offer,
        off.ohc_id_offer,
        off.id_hub_teams AS id_business_unit,
        REPLACE(UPPER(
            CASE
                WHEN offer_flow = 'CENTRAL' AND dr.city_group = 'Porto Alegre' THEN 'CENTRAL POA'
                WHEN offer_flow = 'CENTRAL' AND dr.city_group = 'RMSP' THEN 'CENTRAL SP'
                WHEN offer_flow = 'CENTRAL' AND dr.city_group = 'Rio de Janeiro' THEN 'CENTRAL RJ'
                WHEN offer_flow = 'CENTRAL' THEN 'CENTRAL NO INFO'
                WHEN offer_flow = 'HUB' THEN (CASE WHEN off.ohc_offer_flow_detail IS NULL AND off.vo_id_offer IS NOT NULL THEN off.hub_name_teams ELSE off.ohc_offer_flow_detail END)
                ELSE offer_flow
            END
        ), '  ',' ') AS business_unit,
        offer_flow
    FROM
        offer_flow AS off
    INNER JOIN
        regions AS dr
            ON dr.id_offer = COALESCE(off.id_offer,off.ohc_id_offer)
),
-- OFFERS PORTIFOLIO
offer_portfolio AS (
    SELECT
        id_offer,
        ohc_id_offer,
        CASE
            WHEN bu.business_unit = 'HUB SP - Perdizes'
                THEN to_timestamp('2021-11-01 00:00:00', "yyyy-MM-dd HH:mm:ss")
            WHEN bu.business_unit = 'HUB SP - Bela Vista'
                THEN to_timestamp('2021-11-04 00:00:00', "yyyy-MM-dd HH:mm:ss")
            WHEN bu.business_unit IN ('HUB RJ - Zona Sul','HUB SP - Vila Madalena','HUB SP - Santana','HUB SP - Brooklin')
                THEN to_timestamp('2021-12-01 00:00:00', "yyyy-MM-dd HH:mm:ss")
            WHEN bu.business_unit = 'HUB RS - Porto Alegre'
                THEN to_timestamp('2021-12-03 00:00:00', "yyyy-MM-dd HH:mm:ss")
            WHEN bu.business_unit IN ('HUB SP - Saúde','HUB SP - Vila Mariana','HUB SP - Tatuapé')
                THEN to_timestamp('2021-12-07 00:00:00', "yyyy-MM-dd HH:mm:ss")
            WHEN bu.business_unit IN ('HUB SP - Butantã')
                OR bu.offer_flow = 'HUB'
                    THEN to_timestamp('2021-12-09 00:00:00', "yyyy-MM-dd HH:mm:ss")
            WHEN bu.offer_flow = 'HUB'
                THEN to_timestamp('2022-01-01 00:00:00', "yyyy-MM-dd HH:mm:ss")
        END AS offer_portfolio_start_date
    FROM
        business_unit AS bu
),
-- RANK OFFER
rank_offers AS (
  SELECT
    COALESCE(vo.id_offer, g.id) AS id,
    ROW_NUMBER() OVER (
        PARTITION BY
            COALESCE(vo.id_buyer, g.id_buyer)
                ORDER BY COALESCE(vo.ts_offer_created, g.ts_created)
    ) AS buyer_rank_offers,
    ROW_NUMBER() OVER (
        PARTITION BY
            COALESCE(vo.id_house, g.id_house)
                ORDER BY COALESCE(vo.ts_offer_created, g.ts_created)
    ) AS house_rank_offers
  FROM
        datalake_firestore.sale_offer AS g
    FULL OUTER JOIN
        datalake_sale_offer_flows.sale_offer_flows AS vo
            ON vo.id_offer = g.id
),
-- BUSINESS RULES
business_rules AS (
    SELECT
        COALESCE(ds.vo_id_offer, ds.id_offer,ds.ohc_id_offer) AS id_offer,
        ds.id_sale_flow,
        COALESCE(ds.id_buyer,ds.ohc_id_buyer) AS id_buyer,
        COALESCE(ds.id_house,ds.ohc_id_house) AS id_house,
        dr.id_owner AS id_owner,
        COALESCE(dr.id_region, h.id_region) AS id_region,
        CASE
            WHEN COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= '2021-11-01'
                THEN ds.vo_id_user_agent
            ELSE
                ds.rbo_id_user_agent
        END AS id_user_agent,
        CASE
            WHEN COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= '2021-11-01'
                THEN ds.du_vo_id_agent
            ELSE
                ds.wc_id_agent
        END AS id_agent,
        ds.id_booking,
        ds.id_user_secretariat_booking_creator,
        ds.id_vendas,
        ds.id_pendency,
        ds.vo_id_user_team_lead AS id_user_team_lead,
        COALESCE(busf.id_hub, bu.id_business_unit) AS id_business_unit,
        h.id_company_hubspot AS id_company_supply,
        h.uuid_company AS uuid_company_supply,
        ds.id_company_demand AS id_company_demand,
        CASE
            WHEN COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= '2021-11-01'
                THEN ds.vo_agent_name
            ELSE
                ds.rbo_agent_name
        END AS agent_name,
        ds.pendency,
        ds.pendency_type,
        ds.opportunities_of_the_week,
        CASE
            WHEN COALESCE(ds.vo_tags_from_salesflow, ds.mo_tags_from_salesflow) LIKE "%pre-analise-expansao%"
                OR COALESCE(ds.vo_tags_from_salesflow, ds.mo_tags_from_salesflow) LIKE "%credito-andamento%"
                OR COALESCE(ds.vo_tags_from_salesflow, ds.mo_tags_from_salesflow) LIKE "%credito-aprovado%"
                OR COALESCE(ds.vo_tags_from_salesflow, ds.mo_tags_from_salesflow) LIKE "%credito-recusado%" THEN true
            ELSE false
        END AS has_credit_pre_analysis,
        CASE
            WHEN COALESCE(ds.vo_tags_from_salesflow, ds.mo_tags_from_salesflow) LIKE "%no-protocolo%" THEN true
            WHEN COALESCE(ds.vo_dt_sale_agreement_created, ds.mo_dt_sale_agreement_created) >= "2022-03-14"
                AND ds.current_payment_method LIKE "FINANCED%"
                AND COALESCE(ds.vo_financing_bank, ds.mo_financing_bank) = "Itaú"
                AND COALESCE(ds.vo_credit_model, ds.mo_credit_model) = "ATTA"
                AND dr.city_group = "RMSP" THEN true
            ELSE false
        END AS has_payment_in_protocol,
        has_used_fgts_in_payment,
        has_used_negotiation_chat,
        last_discount_proposed,
        first_discount_proposed,
        current_payment_method,
        vo_payment_method,
        planned_payment_method,
        registry_price,
        itbi_price,
        payment_entry_amount,
        financing_value,
        fgts_value,
        earnest_value,
        COALESCE(giroffer_brokerage_fee, vo_brokerage_fee) AS brokerage_fee,
        off.offer_flow,
        COALESCE(busf.hub_name, bu.business_unit) AS business_unit,
        busf.business_context AS business_context_sales_flow,
        ofp.offer_portfolio_start_date,
        COALESCE(vo_flow_step, monday_status) AS monday_status,
        CASE
            WHEN (vo_sk_team_lead IS NOT NULL
                AND CURRENT_TIMESTAMP() >= ofp.offer_portfolio_start_date)
                    THEN true
            ELSE false
        END AS is_offer_portfolio,
        ds.ohc_offer_flow_detail,
        COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) AS ts_offer_submitted,
        CASE
            WHEN off.offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN (vo_sk_team_lead IS NOT NULL AND CURRENT_TIMESTAMP() >= ofp.offer_portfolio_start_date)
                            AND COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= offer_portfolio_start_date
                                THEN COALESCE(ds.vo_offer_accepted_date, ds.ohc_offer_accepted_date)
                        ELSE COALESCE(ds.ohc_offer_accepted_date, ds.vo_offer_accepted_date)
                    END)
            ELSE COALESCE(ds.mo_offer_accepted_date,ds.vo_offer_accepted_date)
        END AS dt_offer_accepted,
        CASE
            WHEN off.offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN (vo_sk_team_lead IS NOT NULL AND CURRENT_TIMESTAMP() >= ofp.offer_portfolio_start_date)
                            AND COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= offer_portfolio_start_date
                                THEN COALESCE(ds.vo_offer_dismissed_date,ds.ohc_offer_dismissed_date)
                        ELSE COALESCE(ds.ohc_offer_dismissed_date, ds.vo_offer_dismissed_date)
                    END)
            ELSE COALESCE(ds.mo_offer_dismissed_date, ds.vo_offer_dismissed_date)
        END AS dt_offer_dismissed,
        CASE
            WHEN off.offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN (vo_sk_team_lead IS NOT NULL AND CURRENT_TIMESTAMP() >= ofp.offer_portfolio_start_date)
                            AND COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= offer_portfolio_start_date
                                THEN COALESCE(ds.vo_sale_agreement_signed_date, ds.ohc_sale_agreement_signed_date)
                        ELSE COALESCE(ds.ohc_sale_agreement_signed_date, ds.vo_sale_agreement_signed_date)
                    END)
            ELSE COALESCE(ds.mo_sale_agreement_signed_date,ds.vo_sale_agreement_signed_date)
        END AS dt_sale_agreement_signed,
        UPPER(
            CASE
                WHEN off.offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN (vo_sk_team_lead IS NOT NULL AND CURRENT_TIMESTAMP() >= ofp.offer_portfolio_start_date)
                            AND COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= offer_portfolio_start_date
                                THEN ds.vendas_offer_status
                    ELSE COALESCE(ds.ohc_status,ds.vendas_offer_status)
                END)
                ELSE COALESCE(regexp_replace(ds.monday_offer_status,"\\s+","_"), ds.vendas_offer_status)
            END
        ) AS offer_status,
        UPPER(ds.agent_work_contract) AS agent_work_contract,
        ds.vo_sk_team_lead AS id_team_lead,
        UPPER(
            CASE
                WHEN off.offer_flow IN ('HUB','CENTRAL') THEN (
                        CASE
                            WHEN COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= '2021-11-01'
                                THEN ds.vo_team_lead_name
                            ELSE
                                CASE
                                    WHEN (vo_sk_team_lead IS NOT NULL AND CURRENT_TIMESTAMP() >= ofp.offer_portfolio_start_date)
                                        AND COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= offer_portfolio_start_date
                                            THEN ds.vo_team_lead_name
                                    ELSE COALESCE(ds.ohc_team_lead_name,ds.vo_team_lead_name)
                                END
                        END)
                ELSE ds.vo_team_lead_name
            END) AS team_lead_name,
        UPPER(
            CASE
                WHEN COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= '2021-11-01'
                    THEN ds.vo_id_consultant
            ELSE
                CASE
                    WHEN ds.ohc_id_offer IS NOT NULL
                        THEN 'GSHEETS_[]'
                    ELSE COALESCE(ds.vo_id_consultant,ds.mo_id_consultant)
                END
            END
        ) AS id_consultant,
        UPPER(
            CASE
                WHEN COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= '2021-11-01'
                    THEN ds.vo_id_user_consultant
            ELSE
                CASE
                    WHEN ds.ohc_id_offer IS NOT NULL
                        THEN NULL
                    ELSE COALESCE(ds.vo_id_user_consultant,ds.mo_id_user_consultant)
                END
            END
        ) AS id_user_consultant,
        UPPER(
            CASE
                WHEN off.offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= '2021-11-01'
                            THEN ds.vo_consultant_name
                        ELSE
                            CASE
                                WHEN (vo_sk_team_lead IS NOT NULL AND CURRENT_TIMESTAMP() >= ofp.offer_portfolio_start_date)
                                    AND COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= offer_portfolio_start_date
                                        THEN ds.vo_consultant_name
                                ELSE COALESCE(ds.ohc_consultant_name,ds.vo_consultant_name)
                            END
                    END)
                ELSE COALESCE(ds.mo_consultant_name, ds.vo_consultant_name)
            END
        )  AS consultant_name,
        ds.sale_price,
        COALESCE(ds.first_price_offered_by_buyer, ds.mo_price_offered_by_buyer) AS first_price_offered_by_buyer,
        CASE
            WHEN off.offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN (vo_sk_team_lead IS NOT NULL AND CURRENT_TIMESTAMP() >= ofp.offer_portfolio_start_date)
                            AND COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= offer_portfolio_start_date
                                THEN ds.last_price_offered_by_buyer
                        ELSE (
                            CASE
                                WHEN UPPER(ds.ohc_status) IN ('CONTRATO ASSINADO','DESCARTADO')
                                    THEN ds.ohc_sale_price_agreed
                                ELSE COALESCE(ds.last_price_offered_by_buyer,ds.ohc_sale_price_agreed)
                            END
                        )
                    END)
            ELSE COALESCE(ds.last_price_offered_by_buyer,ds.mo_sale_price_agreed)
        END AS last_price_offered_by_buyer,
        vo_sale_price_agreed,
        COALESCE(vo_financing_bank, mo_financing_bank) AS financing_bank,
        COALESCE(vo_id_user_consultant, mo_id_closing_specialist) AS id_closing_specialist,
        COALESCE(vo_sale_agreement_status, mo_sale_agreement_status) AS sale_agreement_status,
        COALESCE(vo_sale_agreement_cancellation_reason, mo_sale_agreement_cancellation_reason) AS sale_agreement_cancellation_reason,
        COALESCE(vo_drop_reason, mo_drop_reason) AS drop_reason,
        COALESCE(offer_acceptance_probability) AS offer_acceptance_probability,
        COALESCE(vo_credit_model, mo_credit_model) AS credit_model,
        COALESCE(vo_closing_status, mo_closing_status) AS closing_status,
        COALESCE(vo_house_dilligence_status, mo_house_dilligence_status) AS house_dilligence_status,
        COALESCE(vo_seller_dilligence_status, mo_seller_dilligence_status) AS seller_dilligence_status,
        COALESCE(vo_report_dilligence_status, mo_report_dilligence_status) AS report_dilligence_status,
        COALESCE(vo_bank_analysis_status, mo_bank_analysis_status) AS bank_analysis_status,
        COALESCE(vo_payment_status, mo_payment_status) AS payment_status,
        COALESCE(vo_payment_model, mo_payment_model) AS payment_model,
        COALESCE(vo_credit_status, mo_credit_status) AS credit_status,
        COALESCE(vo_notary_office_status, mo_notary_office_status) AS notary_office_status,
        vo_notary_office_details AS notary_office_details,
        COALESCE(vo_real_estate_register_office_status, mo_real_estate_register_office_status) AS real_estate_register_office_status,
        mo_early_keys_status AS early_keys_status,
        COALESCE(vo_tags_from_salesflow, mo_tags_from_salesflow) AS tags_from_salesflow,
        COALESCE(vo_has_seller_debt_payments, mo_has_seller_debt_payments) AS has_seller_debt_payments,
        COALESCE(vo_is_ccv_canceled, mo_is_ccv_canceled) AS is_ccv_canceled,
        COALESCE(vo_dt_sale_transacton_paid, mo_dt_sale_transacton_paid) AS dt_sale_transacton_paid,
        COALESCE(vo_dt_house_registry_ended, mo_dt_house_registry_ended) AS dt_house_registry_ended,
        COALESCE(vo_dt_house_registry_started, mo_dt_house_registry_started) AS dt_house_registry_started,
        COALESCE(vo_dt_sale_agreement_cancelled, mo_dt_sale_agreement_cancelled) AS dt_sale_agreement_cancelled,
        COALESCE(vo_dt_sale_agreement_created, mo_dt_sale_agreement_created) AS dt_sale_agreement_created,
        COALESCE(vo_days_sale_agreement_created_to_sale_agreement_signed, mo_days_sale_agreement_created_to_sale_agreement_signed) AS days_sale_agreement_created_to_sale_agreement_signed,
        COALESCE(vo_days_offer_accepted_to_sale_agreement_signed, mo_days_offer_accepted_to_sale_agreement_signed) AS days_offer_accepted_to_sale_agreement_signed,
        COALESCE(vo_days_offer_accepted_to_sale_agreement_created, mo_days_offer_accepted_to_sale_agreement_created) AS days_offer_accepted_to_sale_agreement_created,
        COALESCE(vo_days_offer_accepted_to_offer_dismissed, mo_days_offer_accepted_to_offer_dismissed) AS days_offer_accepted_to_offer_dismissed,
        ds.ts_updated,
        vo_ts_last_updated_pendency AS ts_last_updated_pendency,
        CASE
            WHEN h.is_sale_3p_supply THEN h.partner_3p_supply
        END AS partner_3p_supply,
        ds.partner_3p_demand,
        COALESCE(h.is_sale_3p_supply, FALSE) AS is_3p_supply,
        COALESCE(h.is_3p_supply_5a AND h.is_sale_3p_supply, FALSE) AS is_3p_supply_5a,
        COALESCE(h.is_3p_supply_bh AND h.is_sale_3p_supply, FALSE) AS is_3p_supply_bh,
        ds.is_3p_demand,
        ds.flg_booking_before_offer,
        ds.flg_visit_completed_before_offer,
        ds.hours_booking_to_offer,
        ds.hours_visit_to_offer,
        CASE
            WHEN LOWER(COALESCE(vo_drop_reason_responsible, mo_drop_reason_responsible)) LIKE '%buyer%'
                THEN 'Buyer'
            WHEN LOWER(COALESCE(vo_drop_reason_responsible, mo_drop_reason_responsible)) LIKE '%seller%'
                THEN 'Seller'
            ELSE 'Other'
        END AS drop_reason_responsible,
        COALESCE(vo_diligence_appointment_reason, mo_diligence_appointment_reason) AS diligence_appointment_reason,
        CASE
            WHEN rk.buyer_rank_offers = 1
                THEN TRUE
            ELSE FALSE
        END AS is_buyer_first_offer,
        CASE
            WHEN rk.house_rank_offers = 1
                THEN TRUE
            ELSE FALSE
        END AS is_house_first_offer,
        CASE
            WHEN (vo_sk_team_lead IS NOT NULL AND CURRENT_TIMESTAMP() >= ofp.offer_portfolio_start_date)
                THEN 'PORTFOLIO_NEGOCIACAO'
            WHEN ds.ohc_id_offer IS NOT NULL
                THEN (
                    CASE
                        WHEN ohc_offer_model IS NOT NULL
                            THEN upper(ohc_offer_model)
                        ELSE 'GSHEETS'
                    END
                )
            WHEN ds.vo_id_offer IS NOT NULL
                THEN 'VENDAS'
            WHEN ds.mo_id_offer IS NOT NULL
                THEN 'MONDAY'
            WHEN ds.id_offer IS NOT NULL
                THEN 'GIROFFER'
            ELSE 'NOT DEFINED'
        END AS offer_platform,
        ds.vo_is_a_rescued_ccv AS is_a_rescued_ccv,
        ds.vo_is_a_rescued_offer AS is_a_rescued_offer,
        ds.vo_is_ccv_5a_model AS is_ccv_5a_model,
        ds.vo_dt_sale_agreement_rescued AS dt_sale_agreement_rescued,
        ds.vo_dt_offer_rescued AS dt_offer_rescued,
        ds.vo_ts_seller_fup AS ts_seller_fup,
        ds.vo_ts_buyer_fup AS ts_buyer_fup,
        ds.ts_booking_created
    FROM
        data_sources AS ds
    LEFT JOIN
        regions AS dr
            ON dr.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer)
    LEFT JOIN
        offer_flow AS off
            ON off.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer)
                OR off.ohc_id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer)
    LEFT JOIN
        rank_offers AS rk
            ON rk.id = ds.id_offer
    LEFT JOIN
        business_unit AS bu
            ON bu.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer)
                OR bu.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer)
    LEFT JOIN
        offer_portfolio AS ofp
            ON ofp.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer)
                OR ofp.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer)
    LEFT JOIN
        business_unit_by_hub_id AS busf
            ON busf.id_hub = ds.id_hub
            AND busf.row = 1
            AND ds.id_hub IS NOT NULL
    LEFT JOIN
        datalake_ebdb_listing.house AS h
            ON h.id = COALESCE(ds.id_house,ds.ohc_id_house)
),
-- SECRETARIATS
secretariat_on_offer_submitted_date AS (
    SELECT
        b.id_offer,
        bsc.id_external_responsible AS id_user_secretariat_on_offer_submitted_date
    FROM
        business_rules AS b
    JOIN
        datalake_hub_services.buyer_secretariat_changes AS bsc
            ON b.id_buyer = bsc.id_external_lead
            AND b.ts_offer_submitted BETWEEN bsc.ts_assigned AND COALESCE(bsc.ts_unassigned, NOW())
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY b.id_offer ORDER BY bsc.ts_assigned DESC) = 1
),
secretariat_on_offer_accepted_date AS (
    SELECT
        b.id_offer,
        bsc.id_external_responsible AS id_user_secretariat_on_offer_accepted_date
    FROM
        business_rules AS b
    JOIN
        datalake_hub_services.buyer_secretariat_changes AS bsc
            ON b.id_buyer = bsc.id_external_lead
            AND b.dt_offer_accepted BETWEEN bsc.ts_assigned AND COALESCE(bsc.ts_unassigned, NOW())
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY b.id_offer ORDER BY bsc.ts_assigned DESC) = 1
),
secretariat_on_offer_dismissed_date AS (
    SELECT
        b.id_offer,
        bsc.id_external_responsible AS id_user_secretariat_on_offer_dismissed_date
    FROM
        business_rules AS b
    JOIN
        datalake_hub_services.buyer_secretariat_changes AS bsc
            ON b.id_buyer = bsc.id_external_lead
            AND b.dt_offer_dismissed BETWEEN bsc.ts_assigned AND COALESCE(bsc.ts_unassigned, NOW())
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY b.id_offer ORDER BY bsc.ts_assigned DESC) = 1
),
secretariat_on_sale_agreement_created_date AS (
    SELECT
        b.id_offer,
        bsc.id_external_responsible AS id_user_secretariat_on_sale_agreement_created_date
    FROM
        business_rules AS b
    JOIN
        datalake_hub_services.buyer_secretariat_changes AS bsc
            ON b.id_buyer = bsc.id_external_lead
            AND b.dt_sale_agreement_created BETWEEN bsc.ts_assigned AND COALESCE(bsc.ts_unassigned, NOW())
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY b.id_offer ORDER BY bsc.ts_assigned DESC) = 1
),
secretariat_on_sale_agreement_signed_date AS (
    SELECT
        b.id_offer,
        bsc.id_external_responsible AS id_user_secretariat_on_sale_agreement_signed_date
    FROM
        business_rules AS b
    JOIN
        datalake_hub_services.buyer_secretariat_changes AS bsc
            ON b.id_buyer = bsc.id_external_lead
            AND b.dt_sale_agreement_signed BETWEEN bsc.ts_assigned AND COALESCE(bsc.ts_unassigned, NOW())
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY b.id_offer ORDER BY bsc.ts_assigned DESC) = 1
),
last_secretariat as (
    SELECT
        b.id_offer,
        bsc.id_external_responsible AS id_user_last_secretariat
    FROM
        business_rules AS b
    JOIN
        datalake_hub_services.buyer_secretariat_changes AS bsc
            ON b.id_buyer = bsc.id_external_lead
            AND bsc.is_last_responsible 
)
SELECT
    br.id_offer,
    id_sale_flow,
    id_buyer,
    id_house,
    id_owner,
    id_region,
    id_agent,
    id_team_lead,
    id_user_team_lead,
    CAST(id_user_consultant AS BIGINT) AS id_user_consultant,
    CAST(id_user_agent AS BIGINT) AS id_user_agent,
    id_consultant,
    id_user_secretariat_booking_creator,
    id_user_secretariat_on_offer_submitted_date,
    id_user_secretariat_on_offer_accepted_date,
    id_user_secretariat_on_offer_dismissed_date,
    id_user_secretariat_on_sale_agreement_created_date,
    id_user_secretariat_on_sale_agreement_signed_date,
    id_user_last_secretariat,
    id_booking,
    id_closing_specialist,
    id_vendas,
    id_pendency,
    id_business_unit,
    id_company_supply,
    uuid_company_supply,
    cs_supply.sk_company AS sk_company_supply,
    id_company_demand,
    cs_demand.sk_company AS sk_company_demand,
    pendency,
    CASE
        WHEN current_payment_method = "INSTANT_MORTGAGE" THEN (
            CASE
            WHEN has_payment_in_protocol = true
                AND has_credit_pre_analysis = true THEN "CCV CAVG with Payment in Protocol with Credit Pre Analysis"
            WHEN has_credit_pre_analysis = true THEN "CCV CAVG with Credit Pre Analysis"
            END
        )
        WHEN has_payment_in_protocol = true
            AND has_credit_pre_analysis = true THEN "CCV Payment in Protocol with Credit Pre Analysis"
        WHEN has_payment_in_protocol = true THEN "CCV Payment in Protocol"
        WHEN has_credit_pre_analysis = true THEN "CCV Credit Pre Analysis"
        WHEN credit_model = "ATTA" THEN "Default CCV - 1.Inside Financing"
        WHEN credit_model = "EXTERNAL" THEN "Default CCV - 2.External Financing"
        ELSE "Default CCV - 3.Financing other status"
    END AS ccv_type,
    pendency_type,
    opportunities_of_the_week,
    COALESCE(vo_payment_method, current_payment_method) AS current_payment_method,
    planned_payment_method,
    team_lead_name,
    consultant_name,
    agent_name,
    offer_flow,
    business_unit,
    offer_platform,
    offer_status,
    monday_status,
    credit_model,
    closing_status,
    house_dilligence_status,
    seller_dilligence_status,
    report_dilligence_status,
    bank_analysis_status,
    payment_status,
    payment_model,
    credit_status,
    notary_office_status,
    notary_office_details,
    real_estate_register_office_status,
    early_keys_status,
    tags_from_salesflow,
    sale_agreement_status,
    agent_work_contract,
    financing_bank,
    sale_agreement_cancellation_reason,
    drop_reason,
    drop_reason_responsible,
    diligence_appointment_reason,
    partner_3p_supply,
    partner_3p_demand,
    registry_price,
    itbi_price,
    payment_entry_amount,
    financing_value,
    fgts_value,
    earnest_value,
    brokerage_fee,
    sale_price,
    first_price_offered_by_buyer,
    last_price_offered_by_buyer,
    COALESCE(vo_sale_price_agreed, last_price_offered_by_buyer) AS sale_price_agreed,
    CASE
        WHEN sale_price IS NULL
        OR first_price_offered_by_buyer IS NULL
            THEN NULL
        ELSE 1-1.00*first_price_offered_by_buyer/sale_price
    END AS first_discount_proposed,
    CASE
        WHEN sale_price IS NULL or last_price_offered_by_buyer IS NULL THEN NULL
        ELSE 1-1.00*last_price_offered_by_buyer/sale_price
    END AS last_discount_proposed,
    offer_acceptance_probability,
    days_sale_agreement_created_to_sale_agreement_signed,
    days_offer_accepted_to_sale_agreement_signed,
    days_offer_accepted_to_sale_agreement_created,
    days_offer_accepted_to_offer_dismissed,
    CASE
        WHEN dt_offer_accepted IS NOT NULL
            THEN DATEDIFF(DATE(dt_offer_accepted), DATE(ts_offer_submitted))
        ELSE NULL
    END AS days_offer_submitted_to_offer_accepted,
    CASE
        WHEN dt_sale_agreement_created IS NOT NULL
            THEN DATEDIFF(DATE(dt_sale_agreement_created), DATE(ts_offer_submitted))
        ELSE NULL
    END AS days_offer_submitted_to_sale_agreement_created,
    CASE
        WHEN dt_offer_dismissed IS NOT NULL
            THEN DATEDIFF(DATE(dt_offer_dismissed), DATE(ts_offer_submitted))
        ELSE NULL
    END AS days_offer_submitted_to_offer_dismissed,
    CASE
        WHEN dt_sale_agreement_signed IS NOT NULL
            THEN DATEDIFF(DATE(dt_sale_agreement_signed), DATE(ts_offer_submitted))
        ELSE NULL
    END AS days_offer_submitted_to_sale_agreement_signed,
    hours_booking_to_offer,
    hours_visit_to_offer,
    has_credit_pre_analysis,
    has_payment_in_protocol,
    has_used_fgts_in_payment,
    has_used_negotiation_chat,
    has_seller_debt_payments,
    is_buyer_first_offer,
    is_house_first_offer,
    is_ccv_canceled,
    is_3p_supply,
    is_3p_supply_5a,
    is_3p_supply_bh,
    is_3p_demand,
    is_a_rescued_ccv,
    is_a_rescued_offer,
    is_ccv_5a_model,
    flg_booking_before_offer,
    flg_visit_completed_before_offer,
    ts_booking_created,
    dt_sale_agreement_rescued,
    dt_offer_rescued,
    dt_sale_transacton_paid,
    dt_house_registry_ended,
    dt_house_registry_started,
    dt_sale_agreement_cancelled,
    dt_sale_agreement_created,
    dt_offer_accepted,
    dt_offer_dismissed,
    dt_sale_agreement_signed,
    CURRENT_TIMESTAMP() AS ts_load,
    ts_offer_submitted,
    ts_last_updated_pendency,
    ts_seller_fup,
    ts_buyer_fup,
    ts_updated
FROM
    business_rules AS br
LEFT JOIN
    secretariat_on_offer_submitted_date AS sosd
        ON sosd.id_offer = br.id_offer
LEFT JOIN
    secretariat_on_offer_accepted_date AS soad
        ON soad.id_offer = br.id_offer
LEFT JOIN
    secretariat_on_offer_dismissed_date AS sodd
        ON sodd.id_offer = br.id_offer
LEFT JOIN
    secretariat_on_sale_agreement_created_date AS socd
        ON socd.id_offer = br.id_offer
LEFT JOIN
    secretariat_on_sale_agreement_signed_date AS sosa
        ON sosa.id_offer = br.id_offer
LEFT JOIN
    last_secretariat AS ls
        ON ls.id_offer = br.id_offer
LEFT JOIN
    datalake_rede_company.company_sks AS cs_demand
        ON (br.id_company_demand IS NOT NULL
        AND br.id_company_demand = cs_demand.id_hubspot)
        OR (br.id_company_demand IS NULL
        AND br.partner_3p_demand = cs_demand.extracted_3p_tag)
LEFT JOIN
    datalake_rede_company.company_sks AS cs_supply
        ON (
        br.uuid_company_supply IS NOT NULL
        AND br.uuid_company_supply = cs_supply.uuid_company
        ) OR (
        br.uuid_company_supply IS NULL
        AND br.id_company_supply IS NOT NULL
        AND br.id_company_supply = cs_supply.id_hubspot
        ) OR (
        br.uuid_company_supply IS NULL
        AND br.id_company_supply IS NULL
        AND br.partner_3p_supply = cs_supply.extracted_3p_tag
    )