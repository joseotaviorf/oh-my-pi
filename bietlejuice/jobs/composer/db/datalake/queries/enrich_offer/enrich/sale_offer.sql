-- RELATION BOOKING OFFER
WITH visit_before_offer AS (
    WITH vc_aux AS (
        SELECT
            so.id AS id_offer,
            bs.id AS id_booking,
            bs.id_agent,
            du.id as id_user_agent,
            TRUE AS flg_visit_completed_before_offer,
            (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_created))/(3600) AS hours_booking_to_offer,
            (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_booking_utc))/(3600) AS hours_visit_to_offer,
            ROW_NUMBER() OVER (
                PARTITION BY 
                    so.id  
                ORDER BY 
                    (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_booking_utc))
            ) AS rw_visit_completed
        FROM 
            datalake_firestore.sale_offer AS so
        JOIN 
            datalake_booking.booking AS bs
                ON bs.id_house = so.id_house
                AND bs.id_visitor = so.id_buyer
        LEFT JOIN 
            dw_public.dim_user AS du
                ON bs.id_agent = du.dados_agente_id
        WHERE
            bs.visit_intent = 'SALE'
            AND bs.type = 'Visita'
            AND bs.ts_booking_utc < so.ts_created
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
            so.id AS id_offer,
            bs.id AS id_booking,
            bs.id_agent,
            du.id as id_user_agent,
            TRUE AS flg_booking_before_offer,
            (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_created))/(3600) AS hours_booking_to_offer,
            (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_booking_utc))/(3600) AS hours_visit_to_offer,
            ROW_NUMBER() OVER (
                PARTITION BY 
                    so.id 
                ORDER BY 
                    (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_created))
            ) AS rw_booking
        FROM 
            datalake_firestore.sale_offer AS so
        JOIN 
            datalake_booking.booking AS bs
                ON bs.id_house = so.id_house
                AND bs.id_visitor = so.id_buyer
        LEFT JOIN 
            dw_public.dim_user AS du
                ON bs.id_agent = du.dados_agente_id
        WHERE
            bs.visit_intent = 'SALE'
            AND bs.type = 'Visita'
            AND bs.ts_created < so.ts_created
            AND (bs.visit_fup !='VaiNegociar' OR bs.visit_fup IS NULL)
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
        COALESCE(vo.id_user_agent, bo.id_user_agent) AS id_user_agent,
        COALESCE(vo.hours_booking_to_offer, bo.hours_booking_to_offer) AS hours_booking_to_offer,
        COALESCE(vo.hours_visit_to_offer, bo.hours_visit_to_offer) AS hours_visit_to_offer,
        COALESCE(bo.flg_booking_before_offer,vo.flg_visit_completed_before_offer) AS flg_booking_before_offer,
        vo.flg_visit_completed_before_offer
    FROM 
        visit_before_offer AS vo
    FULL OUTER JOIN 
        booking_before_offer AS bo
            ON bo.id_offer = vo.id_offer
),
-- WORK CONTRACT
work_contract AS (
    WITH agent_contract AS (
        SELECT
            aud.id AS agent_id,
            from_unixtime(ure.ts_revision / 1000) AS agent_contract_timestamp,
            aud.id_work_contract AS workContract_id
        FROM
            datalake_ebdb_clean.agent_data_aud AS aud
        JOIN 
            datalake_ebdb_clean.user_revision_entity AS ure 
                ON aud.REV = ure.id
    ),
    contract_aud AS (
        SELECT
            agent_id,
            du.id AS user_id,
            contract.contract_name,
            agent_contract_timestamp,
            du.dadosagente_ativo,
            RANK() OVER (
                PARTITION BY agent_id
                ORDER BY
                agent_contract_timestamp DESC
            ) AS r
        FROM
            agent_contract AS ac
        INNER JOIN 
            dw_public.dim_user du
                ON du.dados_agente_id = ac.agent_id
        INNER JOIN 
            datalake_ebdb_clean.work_contract AS contract 
                ON ac.workcontract_id = contract.id
    ),
    actual_contract AS (
        SELECT
            agent_id,
            contract_name
        FROM
            contract_aud
        WHERE
            r = 1
    ),
    base_agents AS (
        SELECT
            ca.*,
            LAG(ca.contract_name) OVER(
                PARTITION BY ca.agent_id
                ORDER BY
                ca.r DESC
            ) AS previous_work_contract,
            ac.contract_name AS actual_contract
        FROM
            contract_aud ca
        LEFT JOIN 
            actual_contract ac 
                ON ac.agent_id = ca.agent_id
    )
    SELECT
        agent_id as id_agent,
        user_id as id_user_agent,
        actual_contract,
        contract_name,
        previous_work_contract,
        agent_contract_timestamp AS ts_work_contract_start,
        LEAD(agent_contract_timestamp) OVER(
        PARTITION BY 
            agent_id
            ORDER BY
                r DESC
            ) AS ts_work_contract_end,
        dadosagente_ativo,
        r
    FROM
        base_agents
    WHERE
        previous_work_contract <> contract_name
        OR previous_work_contract IS NULL
    ORDER BY
        1,
        r DESC
),
-- REGIONS
regions AS (
    WITH giroffer_regions AS (
        SELECT
            id AS id_offer,
            id_buyer,
            id_house,
            id_owner,
            ts_created AS ts_offer_created,
            last_price_offered_by_buyer
        FROM
            datalake_firestore.sale_offer AS fso
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
                dw_sale.fact_listings
            ) AS fl_ohc 
                ON fl_ohc.sk_house = ohc.id_house_5a
        LEFT JOIN (
            SELECT
                DISTINCT sk_house,
                sk_region,
                sk_owner
            FROM
                dw_sale.fact_listings
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
        dw_janus.dim_region AS dr 
            ON dr.sk_region = aux.id_region
),
-- DATA SOURCES
data_sources AS (
    SELECT
        -- data from giroffer
        g.id AS id_offer,
        g.id_buyer,
        g.id_house,
        g.id_owner,
        g.ts_created AS ts_offer_created,
        g.sale_price,
        g.first_price_offered_by_buyer,
        g.last_price_offered_by_buyer,
        g.ts_updated,
        g.has_used_fgts_in_payment,
        g.has_used_negotiation_chat,
        g.last_discount_proposed,
        g.first_discount_proposed,
        g.current_payment_method,
        g.planned_payment_method,
        g.registry_price,
        g.itbi_price,
        g.payment_entry_amount,
        g.financing_value,
        g.fgts_value,
        g.earnest_value,
        g.brokerage_fee,
        g.id_sale_flow,
        -- data from relation_booking_offer
        rbo.id_user_agent,
        rbo.id_booking,
        COALESCE(rbo.flg_booking_before_offer,FALSE) AS flg_booking_before_offer,
        COALESCE(rbo.flg_visit_completed_before_offer,FALSE) AS flg_visit_completed_before_offer,
        rbo.hours_booking_to_offer,
        rbo.hours_visit_to_offer, 
        -- data from gsheets
        ohc.id_offer AS ohc_id_offer,
        ohc.id_buyer AS ohc_id_buyer,
        ohc.id_house AS ohc_id_house,
        ohc.status AS ohc_status,
        ohc.offer_model AS ohc_offer_model,
        -- data from work_contract
        wc.id_agent AS id_agent,
        wc.contract_name AS agent_work_contract,
        CASE
            WHEN wc.contract_name LIKE '%HUB%' 
                THEN 'HUB'
            WHEN wc.contract_name LIKE '%CENTRAL%' 
                THEN 'CENTRAL'
            ELSE 'DEAL_MAKING'
        END AS wc_offer_flow,
        CASE 
            WHEN UPPER(wc.contract_name) LIKE '%POA%' 
                THEN REPLACE(REPLACE('HUB PORTO ALEGRE','-',''),'  ',' ')
            WHEN UPPER(wc.contract_name) LIKE '%HAMBURGO%' 
                THEN REPLACE(REPLACE('HUB PORTO ALEGRE','-',''),'  ',' ')
            WHEN UPPER(wc.contract_name) LIKE '%LEOPOLDO%' 
                THEN REPLACE(REPLACE('HUB PORTO ALEGRE','-',''),'  ',' ')
            WHEN UPPER(wc.contract_name) LIKE '%MORUMBI%' 
                THEN REPLACE(REPLACE('HUB BUTANTÃ','-',''),'  ',' ') 
            WHEN UPPER(wc.contract_name) LIKE '%BROOKLYN%' 
                THEN REPLACE(REPLACE('HUB BROOKLIN','-',''),'  ',' ') 
            WHEN UPPER(wc.contract_name) LIKE '%HUB%' 
                THEN REPLACE(REPLACE(UPPER(wc.contract_name),'-',''),'  ',' ')
            ELSE UPPER(wc.contract_name)
        END AS wc_hub_name_ajs,  
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
        vo.id_sales_flow AS id_vendas,
        vo.ts_accepted AS vo_offer_accepted_date,
        vo.ts_discarded AS vo_offer_dismissed_date,
        vo.ts_signed AS vo_sale_agreement_signed_date,
        vo.id_user_consultant AS vo_id_user_consultant,
        vo.vendas_offer_flow,
        vo.consultant_name AS vo_consultant_name,
        vo.team_lead_name AS vo_team_lead_name,
        vo.financing_bank AS vo_financing_bank,
        vo.sale_agreement_status AS vo_sale_agreement_status, 
        vo.negotiation_model AS vo_negotiation_model,
        vo.sale_agreement_cancellation_reason AS vo_sale_agreement_cancellation_reason,
        vo.drop_reason AS vo_drop_reason,
        vo.drop_reason_responsible AS vo_drop_reason_responsible,
        vo.credit_model AS vo_credit_model,
        vo.closing_status AS vo_closing_status,
        vo.house_dilligence_status AS vo_house_dilligence_status,
        vo.seller_dilligence_status AS vo_seller_dilligence_status,
        vo.report_dilligence_status AS vo_report_dilligence_status,
        vo.bank_analysis_status AS vo_bank_analysis_status,
        vo.payment_status AS vo_payment_status,
        vo.credit_status AS vo_credit_status,
        vo.notary_office_status AS vo_notary_office_status,
        vo.real_estate_register_office_status AS vo_real_estate_register_office_status,
        vo.has_seller_debt_payments AS vo_has_seller_debt_payments,
        vo.is_ccv_canceled AS vo_is_ccv_canceled,
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
        mo.negotiation_model AS mo_negotiation_model,
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
        replace(
            replace(reverse(split(mo.id_consultant, ',')) [0], '[', ''),']',''
            ) AS last_id_consultant,
        CASE
            WHEN mo.id_consultant IS NOT NULL 
                THEN 'ID_MONDAY_' || mo.id_consultant
        END AS mo_id_consultant
    FROM
        datalake_firestore.sale_offer AS g
    LEFT JOIN 
        relation_booking_offer AS rbo 
            ON rbo.id_offer = g.id 
    FULL OUTER JOIN datalake_gsheets.sale_hub_offer AS ohc 
        ON ohc.id_offer = g.id
    LEFT JOIN datalake_sale_offer_flows.sale_offer_flows AS vo 
        ON vo.id_offer = g.id
    LEFT JOIN datalake_firestore.monday AS mo 
        ON mo.id_offer = g.id
    LEFT JOIN work_contract AS wc 
        ON wc.id_user_agent = rbo.id_user_agent 
        AND g.ts_created >= wc.ts_work_contract_start
        AND (
            (g.ts_created <= wc.ts_work_contract_end)
            OR (wc.ts_work_contract_end IS NULL)
        )
),
-- OFFER FLOW CTE
offer_flow AS (
    SELECT
        id_offer,
        ohc_id_offer,
        ohc_offer_flow_detail,
        vo_id_offer,
        wc_hub_name_ajs,
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
business_unit AS (
  SELECT
    off.id_offer,
    off.ohc_id_offer,
    REPLACE(UPPER(
      CASE 
          WHEN offer_flow = 'CENTRAL' AND dr.city_group = 'Porto Alegre' THEN 'CENTRAL POA'
          WHEN offer_flow = 'CENTRAL' AND dr.city_group = 'RMSP' THEN 'CENTRAL SP'
          WHEN offer_flow = 'CENTRAL' AND dr.city_group = 'Rio de Janeiro' THEN 'CENTRAL RJ'
          WHEN offer_flow = 'CENTRAL' THEN 'CENTRAL NO INFO'
          WHEN offer_flow = 'HUB' THEN (CASE WHEN off.ohc_offer_flow_detail IS NULL AND off.vo_id_offer IS NOT NULL THEN off.wc_hub_name_ajs ELSE off.ohc_offer_flow_detail END)
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
            WHEN bu.business_unit = 'HUB PERDIZES' 
                THEN to_timestamp('2021-11-01 00:00:00', "yyyy-MM-dd HH:mm:ss")
            WHEN bu.business_unit = 'HUB BELA VISTA' 
                THEN to_timestamp('2021-11-04 00:00:00', "yyyy-MM-dd HH:mm:ss")
            WHEN bu.business_unit IN ('HUB RIO DE JANEIRO','HUB VILA MADALENA','HUB SANTANA','HUB BROOKLIN') 
                THEN to_timestamp('2021-12-01 00:00:00', "yyyy-MM-dd HH:mm:ss")
            WHEN bu.business_unit = 'HUB PORTO ALEGRE' 
                THEN to_timestamp('2021-12-03 00:00:00', "yyyy-MM-dd HH:mm:ss")
            WHEN bu.business_unit IN ('HUB SAÚDE','HUB VILA MARIANA','HUB TATUAPÉ')  
                THEN to_timestamp('2021-12-07 00:00:00', "yyyy-MM-dd HH:mm:ss")
            WHEN bu.business_unit IN ('HUB BUTANTÃ') 
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
    so.id,
    ROW_NUMBER() OVER (
        PARTITION BY 
            so.id_buyer 
                ORDER BY so.ts_created
    ) AS buyer_rank_offers,
    ROW_NUMBER() OVER (
        PARTITION BY 
            so.id_house 
                ORDER BY so.ts_created
    ) AS house_rank_offers
  FROM 
    datalake_firestore.sale_offer AS so
),
-- BUSINESS RULES
business_rules AS (
    SELECT 
        COALESCE(ds.id_offer,ds.ohc_id_offer) AS id_offer,
        ds.id_sale_flow,
        COALESCE(ds.id_buyer,ds.ohc_id_buyer) AS id_buyer,
        COALESCE(ds.id_house,ds.ohc_id_house) AS id_house,
        dr.id_owner AS id_owner,
        dr.id_region AS id_region,
        ds.id_agent AS id_agent,
        ds.id_booking,
        ds.id_vendas,
        has_used_fgts_in_payment,
        has_used_negotiation_chat,
        last_discount_proposed,
        first_discount_proposed,
        current_payment_method,
        planned_payment_method,
        registry_price,
        itbi_price,
        payment_entry_amount,
        financing_value,
        fgts_value,
        earnest_value,
        brokerage_fee,        
        off.offer_flow,
        bu.business_unit,
        ofp.offer_portfolio_start_date,
        monday_status,
        id_user_agent,
        CASE 
            WHEN (vo_sk_team_lead IS NOT NULL 
                AND current_timestamp() >= ofp.offer_portfolio_start_date) 
                    THEN true
            ELSE false
        END AS is_offer_portfolio,
        ds.ohc_offer_flow_detail,
        COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) AS ts_offer_submitted,
        CASE 
            WHEN off.offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE 
                        WHEN (vo_sk_team_lead IS NOT NULL AND current_timestamp() >= ofp.offer_portfolio_start_date) 
                            AND COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= offer_portfolio_start_date 
                                THEN COALESCE(ds.vo_offer_accepted_date, ds.ohc_offer_accepted_date) 
                        ELSE COALESCE(ds.ohc_offer_accepted_date, ds.vo_offer_accepted_date) 
                    END) 
            ELSE COALESCE(ds.mo_offer_accepted_date,ds.vo_offer_accepted_date) 
        END AS dt_offer_accepted,
        CASE 
            WHEN off.offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN (vo_sk_team_lead IS NOT NULL AND current_timestamp() >= ofp.offer_portfolio_start_date) 
                            AND COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= offer_portfolio_start_date 
                                THEN COALESCE(ds.vo_offer_dismissed_date,ds.ohc_offer_dismissed_date) 
                        ELSE COALESCE(ds.ohc_offer_dismissed_date, ds.vo_offer_dismissed_date) 
                    END) 
            ELSE COALESCE(ds.mo_offer_dismissed_date, ds.vo_offer_dismissed_date) 
        END AS dt_offer_dismissed,
        CASE
            WHEN off.offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN (vo_sk_team_lead IS NOT NULL AND current_timestamp() >= ofp.offer_portfolio_start_date) 
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
                        WHEN (vo_sk_team_lead IS NOT NULL AND current_timestamp() >= ofp.offer_portfolio_start_date) 
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
                            WHEN (vo_sk_team_lead IS NOT NULL AND current_timestamp() >= ofp.offer_portfolio_start_date) 
                                AND COALESCE(ds.ts_offer_created, ds.ohc_offer_submitted_date) >= offer_portfolio_start_date 
                                    THEN ds.vo_team_lead_name 
                            ELSE COALESCE(ds.ohc_team_lead_name,ds.vo_team_lead_name) 
                        END) 
                ELSE ds.vo_team_lead_name 
            END) AS team_lead_name, 
        UPPER(
            CASE 
                WHEN ds.ohc_id_offer IS NOT NULL 
                    THEN 'GSHEETS_[]' 
                ELSE COALESCE(ds.vo_id_consultant,ds.mo_id_consultant) 
            END
        ) AS id_consultant,
        sale_price,
        COALESCE(ds.first_price_offered_by_buyer, ds.mo_price_offered_by_buyer) AS first_price_offered_by_buyer,
        CASE
            WHEN off.offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN (vo_sk_team_lead IS NOT NULL AND current_timestamp() >= ofp.offer_portfolio_start_date) 
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
        COALESCE(vo_financing_bank, mo_financing_bank) AS financing_bank,
        COALESCE(vo_id_user_consultant, mo_id_closing_specialist) AS id_closing_specialist,
        COALESCE(vo_sale_agreement_status, mo_sale_agreement_status) AS sale_agreement_status,
        COALESCE(vo_negotiation_model, mo_negotiation_model) AS negotiation_model,
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
        mo_payment_model AS payment_model,
        COALESCE(vo_credit_status, mo_credit_status) AS credit_status,
        COALESCE(vo_notary_office_status, mo_notary_office_status) AS notary_office_status,
        COALESCE(vo_real_estate_register_office_status, mo_real_estate_register_office_status) AS real_estate_register_office_status,
        mo_early_keys_status AS early_keys_status,
        mo_tags_from_salesflow AS tags_from_salesflow,
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
        ts_updated,
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
        mo_diligence_appointment_reason AS diligence_appointment_reason,
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
            WHEN (vo_sk_team_lead IS NOT NULL AND current_timestamp() >= ofp.offer_portfolio_start_date) 
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
        END AS offer_platform
    FROM 
        data_sources AS ds
    LEFT JOIN 
        regions AS dr
            ON dr.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer)
    LEFT JOIN
        offer_flow AS off
            ON off.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer) 
                OR off.ohc_id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer)
    LEFT JOIN rank_offers AS rk
        ON rk.id = ds.id_offer
    LEFT JOIN 
        business_unit AS bu
            ON bu.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer) 
                OR bu.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer)
    LEFT JOIN 
        offer_portfolio AS ofp
            ON ofp.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer) 
                OR ofp.id_offer = COALESCE(ds.id_offer,ds.ohc_id_offer)
)
SELECT 
    id_offer,
    id_sale_flow,
    id_buyer,
    id_house,
    id_owner,
    id_region,
    id_agent,
    id_team_lead,
    id_consultant,
    id_booking,
    id_closing_specialist,
    current_payment_method,
    planned_payment_method,
    team_lead_name,
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
    real_estate_register_office_status,
    early_keys_status,
    tags_from_salesflow,
    sale_agreement_status,
    agent_work_contract,
    financing_bank,
    negotiation_model,
    sale_agreement_cancellation_reason,
    drop_reason,
    drop_reason_responsible,
    diligence_appointment_reason,
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
    last_price_offered_by_buyer AS sale_price_agreed,
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
    has_used_fgts_in_payment,
    has_used_negotiation_chat,
    has_seller_debt_payments,
    is_buyer_first_offer,
    is_house_first_offer,
    is_ccv_canceled,
    flg_booking_before_offer,
    flg_visit_completed_before_offer,
    dt_sale_transacton_paid,
    dt_house_registry_ended,
    dt_house_registry_started,
    dt_sale_agreement_cancelled,
    dt_sale_agreement_created,
    dt_offer_accepted,
    dt_offer_dismissed,
    dt_sale_agreement_signed,
    current_timestamp() AS ts_load,
    ts_offer_submitted,
    ts_updated
FROM
    business_rules