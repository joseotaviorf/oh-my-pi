WITH listing_rent_flows AS (
    WITH reservation AS (
        SELECT
            id_reservation,
            ts_created,
            id_house,
            id_tenant,
            MAX(id_reservation) OVER (PARTITION BY id_house, id_tenant) AS max_id,
            COUNT(1) OVER (PARTITION BY id_house, id_tenant) AS reservation_attempts
        FROM datalake_kill_queue.reservation
    ),
    rent_flows_base AS (
        SELECT
            rent_flow.id_house_rent_flow,
            rent_flow.id_house,
            MAX(dim_house_listing.sk_house_listing) OVER (PARTITION BY rent_flow.id_house, rent_flow.id_house_rent_flow) AS sk_house_listing,
            COALESCE(h.id_region, -1) AS sk_region,
            COALESCE(h.id_condo_parent, -1) AS sk_condo,
            COALESCE(rent_flow.id_rent_flow, -1) AS sk_rent_flow,
            COALESCE(rent_flow.id_booking, -1) AS sk_booking,
            COALESCE(rent_flow.id_owner, -1) AS sk_owner,
            COALESCE(rent_flow.id_user_agent, -1) AS sk_user_agent,
            COALESCE(rent_flow.id_client, -1) AS sk_client,
            COALESCE(rent_flow.id_visit, -1) AS sk_visit,
            COALESCE(dim_offer.sk_offer, -1) AS sk_offer,
            COALESCE(rent_flow.id_proposal, -1) AS sk_proposal,
            COALESCE(dim_contract.sk_contract, -1) AS sk_contract,
            COALESCE(reservation.id_reservation, -1) AS sk_reservation,
            COALESCE(dim_booking.sk_rent_flow_taxonomy, -1) AS sk_rent_flow_taxonomy,
            COALESCE(cs.sk_company, -1) AS sk_company_supply,
            COALESCE(h.country_code, 'Undefined') AS country_code,
            dim_proposal.status AS proposal_status,
            rent_flow.visit_created_type,
            dim_booking.utm_campaign AS booking_utm_campaign,
            dim_booking.utm_content AS booking_utm_content,
            dim_booking.utm_term AS booking_utm_term,
            dim_contract.cancellation_reason AS dimcon_cancellation_reason,
            dim_booking.cancellation_reason AS dimboo_cancellation_reason,
            dim_offer.rejection_reason AS dimoff_cancellation_reason,
            dim_proposal.rejection_reason AS dimprop_cancellation_reason,
            dim_house_listing.ts_listing_version_start AS dt_house_listing,
            rent_flow.dt_booking_created,
            rent_flow.dt_visit,
            rent_flow.dt_client_sign_up,
            dim_offer.dt_first_sent AS dt_offer_submitted,
            rent_flow.dt_proposal_approved,
            dim_proposal.dt_tenant_first_document_sent AS dt_tenant_manual_first_doc_sent,
            dim_proposal.dt_tenant_auto_first_doc_sent,
            dt_tenant_first_document_sent AS dt_tenant_first_doc_sent,
            dt_owner_document_sent AS dt_owner_document_sent,
            rent_flow.dt_contract_created,
            rent_flow.dt_contract_signed,
            dim_proposal.dt_credit_analysis_init,
            dim_proposal.dt_credit_analysis_end,
            dim_proposal.dt_credit_last_approved AS dt_credit_analysis_approved,
            CASE
                WHEN dim_offer.status = 'Aprovada'
                    THEN dim_offer.dt_analysis
                ELSE CAST(NULL AS TIMESTAMP)
            END AS dt_offer_approved,
            CASE
                WHEN dim_offer.status IN ('Aprovada', 'Rejeitada')
                    THEN dim_offer.dt_analysis
                ELSE CAST(NULL AS TIMESTAMP)
            END AS dt_internal_analysis,
            CASE
                WHEN dim_proposal.status IN ('Aprovada', 'Rejeitada')
                    THEN dim_proposal.dt_updated
                ELSE CAST(NULL AS TIMESTAMP)
            END AS dt_credit_analysis, -- old credit analysis date
            dim_proposal.ts_processed AS ts_proposal_processed,
            dim_contract.ts_canceled AS ts_contract_canceled,
            CASE
                WHEN dim_contract.status IN ('Ativo', 'Finalizado')
                    THEN dim_contract.ts_signature
                ELSE CAST(NULL AS TIMESTAMP)
            END AS ts_contract_valid_signature,
            CASE
                WHEN dim_proposal.status = 'Rejeitada'
                    THEN dim_proposal.ts_processed
                ELSE CAST(NULL AS TIMESTAMP)
            END AS ts_proposal_rejected,
            CAST(rent_flow.is_visit_completed AS BOOLEAN) AS is_visit_completed,
            CAST(rent_flow.is_visit_performed AS BOOLEAN) AS is_visit_performed,
            CAST(dim_proposal.tenant_document_sent AS BOOLEAN) AS has_tenant_sent_doc,
            CAST(rent_flow.is_visit_created_from_app AS BOOLEAN) AS is_visit_created_from_app,
            CAST(rent_flow.is_visit_last_updated_from_app AS BOOLEAN) AS is_visit_last_updated_from_app,
            COALESCE(CAST(DATE_FORMAT(rent_flow.dt_house_first_listing, "yyyyMMdd") AS BIGINT), -1) AS sk_house_first_listing_date,
            COALESCE(CAST(DATE_FORMAT(dim_house_listing.ts_listing_version_start, "yyyyMMdd") AS BIGINT), -1) AS sk_house_listing_date,
            COALESCE(CAST(DATE_FORMAT(dim_house_listing.ts_last_de_publication, "yyyyMMdd") AS BIGINT), -1) AS sk_house_listing_de_publication_date,
            COALESCE(
                CAST(
                    DATE_FORMAT(
                        MIN(dim_offer.dt_created) OVER (PARTITION BY rent_flow.id_house)
                        , 'yyyyMMdd'
                    ) AS BIGINT),
                -1) AS sk_house_listing_first_offer_submitted_date,
            COALESCE(CAST(DATE_FORMAT(rent_flow.dt_booking_created, "yyyyMMdd") AS BIGINT), -1) AS sk_booking_created_date,
            COALESCE(CAST(DATE_FORMAT(rent_flow.dt_visit, "yyyyMMdd") AS BIGINT), -1) AS sk_visit_date,
            COALESCE(CAST(DATE_FORMAT(rent_flow.dt_agent_sign_up, "yyyyMMdd") AS BIGINT), -1) AS sk_agent_sign_up_date,
            COALESCE(CAST(DATE_FORMAT(rent_flow.dt_client_sign_up, "yyyyMMdd") AS BIGINT), -1) AS sk_client_sign_up_date,
            COALESCE(CAST(DATE_FORMAT(dim_offer.dt_first_sent, "yyyyMMdd") AS BIGINT), -1) AS sk_offer_submitted_date,
            CASE
                WHEN dim_offer.status = 'Aprovada'
                    THEN COALESCE(CAST(DATE_FORMAT(dim_offer.dt_analysis, "yyyyMMdd") AS BIGINT), -1)
                ELSE -1
            END AS sk_offer_approved_date,
            COALESCE(CAST(DATE_FORMAT(rent_flow.dt_proposal_approved, "yyyyMMdd") AS BIGINT), -1) AS sk_proposal_approved_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_tenant_first_document_sent, "yyyyMMdd") AS BIGINT), -1) AS sk_tenant_manual_first_doc_sent_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_tenant_auto_first_doc_sent, "yyyyMMdd") AS BIGINT), -1) AS sk_tenant_auto_first_doc_sent_date,
            COALESCE(CAST(DATE_FORMAT(dim_contract.ts_created, "yyyyMMdd") AS BIGINT), -1) AS sk_contract_created_date,
            COALESCE(CAST(DATE_FORMAT(dim_contract.ts_signature, "yyyyMMdd") AS BIGINT), -1) AS sk_contract_signed_date,
            COALESCE(CAST(DATE_FORMAT(dim_contract.dt_annulment, "yyyyMMdd") AS BIGINT), -1) AS sk_contract_annulment_date,
            COALESCE(CAST(DATE_FORMAT(dim_contract.ts_canceled, "yyyyMMdd") AS BIGINT), -1) AS sk_contract_canceled_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_credit_analysis_first_init, "yyyyMMdd") AS BIGINT), -1) AS sk_credit_analysis_first_init_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_credit_analysis_last_init, "yyyyMMdd") AS BIGINT), -1) AS sk_credit_analysis_last_init_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_credit_analysis_init, "yyyyMMdd") AS BIGINT), -1) AS sk_credit_analysis_init_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_credit_analysis_first_end, "yyyyMMdd") AS BIGINT), -1) AS sk_credit_analysis_first_end_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_credit_analysis_last_end, "yyyyMMdd") AS BIGINT), -1) AS sk_credit_analysis_last_end_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_credit_analysis_end, "yyyyMMdd") AS BIGINT), -1) AS sk_credit_analysis_end_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_credit_last_approved, "yyyyMMdd") AS BIGINT), -1) AS sk_credit_analysis_approved_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_tenant_first_doc_complete, "yyyyMMdd") AS BIGINT), -1) AS sk_tenant_first_doc_complete_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_tenant_last_doc_complete, "yyyyMMdd") AS BIGINT), -1) AS sk_tenant_last_doc_complete_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_tenant_doc_complete, "yyyyMMdd") AS BIGINT), -1) AS sk_tenant_doc_complete_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_first_credit_evaluation_init, "yyyyMMdd") AS BIGINT), -1) AS sk_first_credit_evaluation_init_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_last_credit_evaluation_init, "yyyyMMdd") AS BIGINT), -1) AS sk_last_credit_evaluation_init_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_first_credit_evaluation_positive, "yyyyMMdd") AS BIGINT), -1) AS sk_first_credit_evaluation_positive_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_last_credit_evaluation_positive, "yyyyMMdd") AS BIGINT), -1) AS sk_last_credit_evaluation_positive_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_first_credit_evaluation_negative, "yyyyMMdd") AS BIGINT), -1) AS sk_first_credit_evaluation_negative_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_last_credit_evaluation_negative, "yyyyMMdd") AS BIGINT), -1) AS sk_last_credit_evaluation_negative_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_guarantee, "yyyyMMdd") AS BIGINT), -1) AS sk_guarantee_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_first_doc_analysis_approved, "yyyyMMdd") AS BIGINT), -1) AS sk_first_doc_analysis_approved_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_last_doc_analysis_approved, "yyyyMMdd") AS BIGINT), -1) AS sk_last_doc_analysis_approved_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_first_doc_analysis_rejected, "yyyyMMdd") AS BIGINT), -1) AS sk_first_doc_analysis_rejected_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_last_doc_analysis_rejected, "yyyyMMdd") AS BIGINT), -1) AS sk_last_doc_analysis_rejected_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.dt_guarantee_paid, "yyyyMMdd") AS BIGINT), -1) AS sk_guarantee_paid_date,
            COALESCE(CAST(DATE_FORMAT(dim_proposal.ts_processed, "yyyyMMdd") AS BIGINT), -1) AS sk_proposal_processed_date,
            COALESCE(CAST(DATE_FORMAT(ar.ts_rating_created, "yyyyMMdd") AS BIGINT), -1) AS sk_agent_review_rating_date,
            COALESCE(CAST(DATE_FORMAT(reservation.ts_created, "yyyyMMdd") AS BIGINT), -1) AS sk_reservation_created_date,
            CAST(reservation.reservation_attempts AS SMALLINT) AS reservation_attempts,
            COALESCE(CAST(dim_proposal.dt_credit_last_approved AS TIMESTAMP),CAST(NULL AS TIMESTAMP)) AS ts_credit_last_approved,
            COALESCE(CAST(dim_contract.ts_signature AS TIMESTAMP),CAST(NULL AS TIMESTAMP)) AS ts_contract_signed,
            COALESCE(CAST(dim_contract.ts_created AS TIMESTAMP),CAST(NULL AS TIMESTAMP)) AS ts_contract_created,
            CAST(NOW() AS TIMESTAMP) AS ts_load
        FROM 
            datalake_ebdb_rent_flow.rent_flow
        JOIN 
            dw_rent.dim_house_listing -- 1:M (M rent_flow x 1 listing)
                ON dim_house_listing.id_house = rent_flow.id_house
                AND COALESCE(rent_flow.dt_rent_flow_created, '1900-01-01') BETWEEN
                    COALESCE(dim_house_listing.ts_listing_version_start, '1900-01-01')
                    AND COALESCE(dim_house_listing.ts_listing_version_end, NOW())
        LEFT JOIN 
            datalake_ebdb_listing.house h
                ON dim_house_listing.id_house = h.id
        LEFT JOIN 
            dw_rent.dim_offer
                ON dim_offer.sk_offer = COALESCE(rent_flow.id_offer_context, -1)
                AND dim_offer.sk_offer != -1
        LEFT JOIN 
            dw_rent.dim_proposal
                ON rent_flow.id_proposal = dim_proposal.id_proposal
        LEFT JOIN
            datalake_ebdb_clean.contract AS con
                ON con.id_house = rent_flow.id_house
                AND con.id = rent_flow.id_contract
        LEFT JOIN
            dw_rent.dim_contract
                ON dim_contract.sk_contract = COALESCE(con.id, -1)
        LEFT JOIN
        /*
        dim_house_listing can be associated with the rent_flow
        or with the contract period. As we know nowdays, a rent_flow can
        starts before the listing starts and it is generating
        an erronous relationship with listing. To solve this while
        we align with SWE a permanent solution, we are giving priority
        to contract association with listing, instead of rent_flow.
        */
            dw_rent.dim_house_listing AS dhl_contract
                ON con.id_house = dhl_contract.id_house
                AND dim_contract.ts_created BETWEEN COALESCE(dhl_contract.ts_listing_version_start, '2000-01-01 00:00:00') AND COALESCE(dhl_contract.ts_listing_version_end, CURRENT_DATE)
        LEFT JOIN 
            datalake_ebdb_agents.agents_review ar
                ON rent_flow.id_booking = ar.id_booking
        LEFT JOIN 
            reservation
                ON reservation.max_id = reservation.id_reservation
                AND rent_flow.id_house = reservation.id_house
                AND rent_flow.id_client = id_tenant
                AND dim_offer.status = 'Aprovada'
                AND reservation.ts_created BETWEEN
                    COALESCE(dim_house_listing.ts_listing_version_start, '1900-01-01')
                    AND COALESCE(dim_house_listing.ts_listing_version_end, NOW())
                AND reservation.ts_created BETWEEN
                    COALESCE(dim_offer.dt_created, '1900-01-01')
                    AND COALESCE(dim_proposal.ts_processed, dim_proposal.dt_updated)
        LEFT JOIN 
            dw_public.dim_booking
                ON dim_booking.sk_booking = rent_flow.id_booking
        LEFT JOIN
            datalake_rede_company.company_sks AS cs
                ON h.is_rent_3p_supply
                AND ((
                    h.uuid_company IS NOT NULL
                    AND h.uuid_company = cs.uuid_company
                ) OR (
                    h.uuid_company IS NULL
                    AND h.id_company_hubspot IS NOT NULL
                    AND h.id_company_hubspot = cs.id_hubspot
                ) OR (
                    h.uuid_company IS NULL
                    AND h.id_company_hubspot IS NULL
                    AND h.partner_3p_supply = cs.extracted_3p_tag
                ))
        WHERE 
            dim_house_listing.is_for_rent
            AND (
                COALESCE(dim_booking.visit_intent, '') <> 'SALE'
                -- The OR condition is covering cases where the last booking, that resulted ON a contract,
                -- had it's visit_intent marked AS SALE, but resulted ON a Rent contract.
                OR (
                    dim_booking.visit_intent = 'SALE'
                    AND rent_flow.id_contract IS NOT NULL
                    )
                )
    ),
    sla_working_minutes AS (
        SELECT
            sla.sk_contract,
            sla.sk_proposal,
            sla.ca2cc_working_minutes,
            sla.ca2cs_working_minutes,
            sla.cc2cs_working_minutes
        FROM
        (
            SELECT
                rf.sk_contract,
                rf.sk_proposal,
                COALESCE(rf.ts_credit_last_approved, TIMESTAMP '1900-01-01') AS ts_credit_last_approved,
                COALESCE(rf.ts_contract_created, TIMESTAMP '1900-01-01') AS ts_contract_created,
                COALESCE(rf.ts_contract_signed, TIMESTAMP '1900-01-01') AS ts_contract_signed,
                CAST(FINTECHOPS_WORK_MIN_SLA(coalesce(ts_credit_last_approved, TIMESTAMP '1900-01-01'),coalesce(ts_contract_created, TIMESTAMP '1900-01-01')) AS FLOAT) AS ca2cc_working_minutes,
                CAST(FINTECHOPS_WORK_MIN_SLA(coalesce(ts_credit_last_approved, TIMESTAMP '1900-01-01'),coalesce(ts_contract_signed, TIMESTAMP '1900-01-01')) AS FLOAT) ca2cs_working_minutes,
                CAST(FINTECHOPS_WORK_MIN_SLA(coalesce(ts_contract_created, TIMESTAMP '1900-01-01'),coalesce(ts_contract_signed, TIMESTAMP '1900-01-01')) AS FLOAT) cc2cs_working_minutes
                -- generic date 1900-01-01 is being used as a workaround for null dates error. Businesstimedelta cant handle null dates.
            FROM
                rent_flows_base rf
        ) sla
        WHERE
            sla.ts_credit_last_approved <> CAST('1900-01-01' AS TIMESTAMP)
            AND sla.ts_contract_created <> CAST('1900-01-01' AS TIMESTAMP)
            AND sla.ts_contract_signed <> CAST('1900-01-01' AS TIMESTAMP)
    )
    SELECT
        rent_flows_base.*,
        COALESCE(
            MIN(
                CASE
                    WHEN sk_offer_submitted_date != -1
                        THEN sk_offer_submitted_date
                    ELSE
                        NULL
                    END
                ) OVER (PARTITION BY id_house), -1
                ) AS sk_min_offer_submitted_date,
	    CASE
	        WHEN sk_tenant_auto_first_doc_sent_date = -1
	            THEN sk_tenant_manual_first_doc_sent_date
	        ELSE sk_tenant_auto_first_doc_sent_date
        END AS sk_tenant_first_doc_sent_date,
        -- SparkSQL's datediff ignores the time part, so we get the seconds diff and convert it to integer days.
        -- 60s*60m*24h = 86400s
        CAST((CAST(CAST(dt_visit AS TIMESTAMP) AS LONG) - CAST(CAST(dt_booking_created AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_booking_created_to_visit,
        CAST((CAST(CAST(dt_visit AS TIMESTAMP) AS LONG) - CAST(CAST(dt_client_sign_up AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_user_created_to_visit,
        CAST((CAST(CAST(dt_internal_analysis AS TIMESTAMP) AS LONG) - CAST(CAST(dt_offer_submitted AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_offer_submitted_to_internal_analysis,
        CAST((CAST(CAST(dt_tenant_first_doc_sent AS TIMESTAMP) AS LONG) - CAST(CAST(dt_offer_approved AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_offer_approved_to_doc_first_sent,
        CAST((CAST(CAST(dt_owner_document_sent AS TIMESTAMP) AS LONG) - CAST(CAST(dt_offer_approved AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_offer_approved_to_owner_doc_sent,
        CAST((CAST(
            COALESCE(
                CAST(dt_credit_analysis_end AS TIMESTAMP),
                CAST(dt_credit_analysis AS TIMESTAMP)
            )
            AS LONG) - CAST(CAST(dt_tenant_first_doc_sent AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_first_doc_sent_to_credit_processed,
        CAST((CAST(CAST(dt_credit_analysis_init AS TIMESTAMP) AS LONG) - CAST(CAST(dt_tenant_first_doc_sent AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_first_doc_sent_to_doc_completed,
        CAST((CAST(
            COALESCE(
                CAST(dt_credit_analysis_end AS TIMESTAMP),
                CAST(dt_credit_analysis AS TIMESTAMP)
            )
            AS LONG) - CAST(CAST(dt_credit_analysis_init AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_doc_completed_to_credit_processed,
        CAST((CAST(CAST(dt_contract_created AS TIMESTAMP) AS LONG) - CAST(CAST(dt_credit_analysis_approved AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_credit_approved_to_contract_created,
        CAST((CAST(CAST(dt_contract_signed AS TIMESTAMP) AS LONG) - CAST(CAST(dt_credit_analysis_approved AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_credit_approved_to_contract_signed,
        CAST((CAST(CAST(dt_contract_signed AS TIMESTAMP) AS LONG) - CAST(CAST(dt_contract_created AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_contract_created_to_contract_signed,
        CAST((CAST(CAST(dt_contract_signed AS TIMESTAMP) AS LONG) - CAST(CAST(dt_booking_created AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_booking_created_to_contract_signed,
        CAST((CAST(CAST(dt_contract_signed AS TIMESTAMP) AS LONG) - CAST(CAST(dt_visit AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_visit_to_contract_signed,
        CAST((CAST(CAST(dt_offer_submitted AS TIMESTAMP) AS LONG) - CAST(CAST(dt_visit AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_visit_to_offer_submitted,
        CAST((CAST(CAST(dt_offer_submitted AS TIMESTAMP) AS LONG) - CAST(CAST(dt_booking_created AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_booking_created_to_offer_submitted,
        CAST((CAST(CAST(dt_credit_analysis_approved AS TIMESTAMP) AS LONG) - CAST(CAST(dt_tenant_first_doc_sent AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_tenant_first_doc_sent_to_insurance_approved,
        CAST((CAST(CAST(dt_contract_signed AS TIMESTAMP) AS LONG) - CAST(CAST(dt_credit_analysis_approved AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_insurance_approved_to_contract_signed,
        CAST((CAST(CAST(dt_tenant_first_doc_sent AS TIMESTAMP) AS LONG) - CAST(CAST(dt_offer_approved AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_offer_approved_to_tenant_first_doc_sent,
        CAST((CAST(CAST(dt_offer_approved AS TIMESTAMP) AS LONG) - CAST(CAST(dt_offer_submitted AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_offer_submitted_to_offer_approved,
        CAST((CAST(CAST(dt_credit_analysis_init AS TIMESTAMP) AS LONG) - CAST(CAST(dt_offer_approved AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_offer_approved_to_credit_init,
        CAST((CAST(CAST(dt_contract_signed AS TIMESTAMP) AS LONG) - CAST(CAST(dt_offer_submitted AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_offer_submitted_to_contract_signed,
        CAST((CAST(CAST(dt_contract_signed AS TIMESTAMP) AS LONG) - CAST(CAST(dt_offer_approved AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_offer_approved_to_contract_signed,
        CAST((CAST(CAST(dt_credit_analysis_approved AS TIMESTAMP) AS LONG) - CAST(CAST(dt_credit_analysis_init AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_tenant_doc_completed_to_credit_approved,
        CAST((CAST(CAST(dt_credit_analysis_init AS TIMESTAMP) AS LONG) - CAST(CAST(dt_tenant_first_doc_sent AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_tenant_first_doc_sent_to_doc_completed,
        CAST((CAST(CAST(dt_contract_signed AS TIMESTAMP) AS LONG) - CAST(CAST(dt_house_listing AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_house_listing_to_contract_signed,
        CAST((CAST(CAST(dt_visit AS TIMESTAMP) AS LONG) - CAST(CAST(dt_house_listing AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_house_listing_to_visit,
        CAST((CAST(
            COALESCE(
                CAST(ts_contract_valid_signature AS TIMESTAMP),
                CAST(ts_contract_canceled AS TIMESTAMP),
                CAST(ts_proposal_rejected AS TIMESTAMP)
            )
            AS LONG) - CAST(CAST(dt_credit_analysis_approved AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_credit_approved_to_closing_processed,
        CAST((CAST(
            COALESCE(
                CAST(dt_tenant_first_doc_sent AS TIMESTAMP),
                (CASE
                    WHEN proposal_status = 'Rejeitada'
                        AND NOT has_tenant_sent_doc
                        THEN ts_proposal_processed
                    ELSE
                        NULL
                END)
            )
            AS LONG) - CAST(CAST(dt_offer_approved AS TIMESTAMP) AS LONG))/(86400) AS DECIMAL(14,2)) AS days_offer_approved_to_doc_contact,
        CASE
            WHEN sk_contract_signed_date > 0
                THEN 'contract_signed'
            WHEN sk_contract_created_date > 0
                AND sk_contract_signed_date < 0
                THEN 'contract_created'
            WHEN sk_credit_analysis_approved_date > 0
                AND (sk_credit_analysis_approved_date >= sk_booking_created_date
                    OR sk_contract_created_date < 0)
                THEN 'credit_approved'
            WHEN sk_credit_analysis_init_date > 0
                AND (sk_credit_analysis_approved_date < 0
                    OR sk_tenant_first_doc_complete_date > 0)
                THEN 'document_completed'
            WHEN (
                    CASE
                        WHEN sk_tenant_auto_first_doc_sent_date = -1
                            THEN sk_tenant_manual_first_doc_sent_date
                        ELSE sk_tenant_auto_first_doc_sent_date
                    END
                ) > 0 -- sk_tenant_first_doc_sent_date
                AND sk_credit_analysis_init_date < 0
                THEN 'document_sent'
            WHEN sk_offer_approved_date > 0
                AND (
                    CASE
                        WHEN sk_tenant_auto_first_doc_sent_date = -1
                            THEN sk_tenant_manual_first_doc_sent_date
                        ELSE sk_tenant_auto_first_doc_sent_date
                    END
                ) < 0 -- sk_tenant_first_doc_sent_date
                THEN 'offer_approved'
            WHEN sk_offer_submitted_date > 0
                AND sk_offer_approved_date < 0
                THEN 'offer_submitted'
            WHEN (sk_booking_created_date > 0
                    OR sk_booking > 0)
                AND is_visit_completed
                THEN 'visit_completed'
            WHEN (sk_booking_created_date > 0
                    OR sk_booking > 0)
                AND NOT COALESCE(is_visit_completed, FALSE)
                THEN 'visit_booked'
        ELSE NULL END AS funnel_step,
        sla.ca2cc_working_minutes AS ca2cc_working_minutes,
        sla.ca2cs_working_minutes AS ca2cs_working_minutes,
        sla.cc2cs_working_minutes AS cc2cs_working_minutes
    FROM
        rent_flows_base
    LEFT JOIN 
        sla_working_minutes sla 
            ON rent_flows_base.sk_proposal = sla.sk_proposal
            AND rent_flows_base.sk_contract = sla.sk_contract
)
SELECT
    id_house_rent_flow AS ods_id,
    sk_house_listing,
    sk_region,
    sk_condo,
    sk_rent_flow,
    sk_booking,
    sk_booking AS sk_tenant_booking_review,
    sk_owner,
    sk_user_agent,
    sk_client,
    sk_visit,
    sk_offer,
    sk_reservation,
    sk_proposal,
    sk_contract,
    sk_rent_flow_taxonomy,
    sk_company_supply,
    sk_house_first_listing_date,
    sk_house_listing_date,
    sk_house_listing_de_publication_date,
    sk_house_listing_first_offer_submitted_date,
    sk_booking_created_date,
    sk_visit_date,
    sk_agent_sign_up_date,
    sk_client_sign_up_date,
    sk_offer_submitted_date,
    sk_min_offer_submitted_date,
    sk_offer_approved_date,
    sk_reservation_created_date,
    sk_proposal_approved_date,
    sk_proposal_processed_date,
    sk_tenant_first_doc_sent_date,
    sk_tenant_manual_first_doc_sent_date,
    sk_tenant_auto_first_doc_sent_date,
    sk_tenant_first_doc_complete_date,
    sk_tenant_last_doc_complete_date,
    sk_tenant_doc_complete_date,
    sk_contract_created_date,
    sk_contract_signed_date,
    sk_contract_annulment_date,
    sk_contract_canceled_date,
    sk_credit_analysis_first_init_date,
    sk_credit_analysis_last_init_date,
    sk_credit_analysis_init_date,
    sk_credit_analysis_first_end_date,
    sk_credit_analysis_last_end_date,
    sk_credit_analysis_end_date,
    sk_credit_analysis_approved_date,
    sk_first_credit_evaluation_init_date AS sk_first_credit_evaluation_init,
    sk_last_credit_evaluation_init_date AS sk_last_credit_evaluation_init,
    sk_first_credit_evaluation_positive_date AS sk_first_credit_evaluation_positive,
    sk_last_credit_evaluation_positive_date AS sk_last_credit_evaluation_positive,
    sk_first_credit_evaluation_negative_date AS sk_first_credit_evaluation_negative,
    sk_last_credit_evaluation_negative_date AS sk_last_credit_evaluation_negative,
    sk_guarantee_date,
    sk_first_doc_analysis_approved_date AS sk_first_doc_analysis_approved,
    sk_last_doc_analysis_approved_date AS sk_last_doc_analysis_approved,
    sk_first_doc_analysis_rejected_date AS sk_first_doc_analysis_rejected,
    sk_last_doc_analysis_rejected_date AS sk_last_doc_analysis_rejected,
    sk_guarantee_paid_date,
    sk_agent_review_rating_date,
    country_code,
    visit_created_type,
    booking_utm_campaign,
    booking_utm_content,
    booking_utm_term,
    funnel_step,
    CASE
        WHEN funnel_step IN ('contract_signed',
                             'contract_created',
                             'credit_approved')
            THEN dimcon_cancellation_reason
        WHEN funnel_step = 'offer_submitted'
            THEN dimoff_cancellation_reason
        WHEN funnel_step IN ('document_completed',
                             'document_sent',
                             'offer_approved')
            THEN dimprop_cancellation_reason
        WHEN funnel_step IN ('visit_completed',
                             'visit_booked')
        THEN dimboo_cancellation_reason
        ELSE 'Not Mapped'
    END AS funnel_step_drop_reason,
    is_visit_completed AS flg_visit_completed,
    is_visit_performed AS flg_visit_performed,
    is_visit_created_from_app AS flg_visit_created_from_app,
    is_visit_last_updated_from_app AS flg_visit_last_updated_from_app,
    reservation_attempts,
    days_booking_created_to_visit,
    days_user_created_to_visit,
    days_offer_submitted_to_internal_analysis,
    days_offer_approved_to_doc_first_sent,
    days_offer_approved_to_owner_doc_sent,
    days_first_doc_sent_to_credit_processed,
    days_first_doc_sent_to_doc_completed,
    days_doc_completed_to_credit_processed,
    days_credit_approved_to_contract_created,
    days_credit_approved_to_contract_signed,
    days_contract_created_to_contract_signed,
    days_booking_created_to_contract_signed,
    days_visit_to_contract_signed,
    days_visit_to_offer_submitted,
    days_booking_created_to_offer_submitted,
    days_tenant_first_doc_sent_to_insurance_approved,
    days_insurance_approved_to_contract_signed,
    days_offer_approved_to_tenant_first_doc_sent,
    days_offer_submitted_to_offer_approved,
    days_offer_approved_to_credit_init,
    days_offer_submitted_to_contract_signed,
    days_offer_approved_to_contract_signed,
    days_tenant_doc_completed_to_credit_approved,
    days_tenant_first_doc_sent_to_doc_completed,
    days_house_listing_to_contract_signed,
    days_house_listing_to_visit,
    days_credit_approved_to_closing_processed,
    days_offer_approved_to_doc_contact,
    ca2cc_working_minutes AS working_min_credit_approved_to_contract_created,
    ca2cs_working_minutes AS working_min_credit_approved_to_contract_signed,
    cc2cs_working_minutes AS working_min_contract_created_to_contract_signed,
    ts_load
FROM
    listing_rent_flows
