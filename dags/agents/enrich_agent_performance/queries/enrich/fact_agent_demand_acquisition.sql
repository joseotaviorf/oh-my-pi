WITH referrer_user AS (
    SELECT
        ebdb_user.id,
        ebdb_user.id_agent,
        ebdb_user.uuid_person,
        ebdb_user.is_active,
        ROW_NUMBER() OVER (
            PARTITION BY
                ebdb_user.id_agent
            ORDER BY
                ebdb_user.is_active DESC,
                ebdb_user.id
        ) AS user_rank
    FROM
        datalake_ebdb_user.user AS ebdb_user
    WHERE
        ebdb_user.country_code = 'BR'
        AND ebdb_user.id_agent IS NOT NULL
),
sale_tqc_offer AS (
    SELECT
        sale_offer.id_buyer,
        tqc_user.id_agent AS id_agent_data,
        sale_offer.id_offer,
        sale_offer.id_house,
        sale_offer.id_user_agent,
        sale_offer.id_user_consultant,
        sale_offer.id_user_team_lead,
        offer_specialists.id_user_agent_lead_referral,
        offer_specialists.id_agent_lead_referral,
        offer_specialists.ts_agent_lead_referral_updated,
        sale_offer.ts_offer_submitted,
        ROW_NUMBER() OVER (
            PARTITION BY
                sale_offer.id_buyer,
                COALESCE(
                    tqc_user.id_agent,
                    offer_specialists.id_user_agent_lead_referral
                )
            ORDER BY
                sale_offer.ts_offer_submitted ASC,
                sale_offer.id_offer ASC
        ) AS offer_rank
    FROM
        datalake_sale_offer_flows.offer_specialists AS offer_specialists
    INNER JOIN
        datalake_sale_offer.sale_offer AS sale_offer
            ON offer_specialists.id_offer = sale_offer.id_offer
    LEFT JOIN
        datalake_ebdb_user.user AS tqc_user
            ON offer_specialists.id_user_agent_lead_referral = tqc_user.id
            AND tqc_user.country_code = 'BR'
    WHERE
        offer_specialists.id_user_agent_lead_referral IS NOT NULL
),
rent_contract_signed AS (
    SELECT
        rent_event.id_tenant_prospect AS id_lead,
        rent_event.id_agent AS id_user_agent,
        rent_event.id_offer AS id_rent_offer,
        rent_event.id_contract AS id_rent_contract,
        rent_event.id_house,
        rent_event.ts_event AS ts_rent_contract_signed,
        ROW_NUMBER() OVER (
            PARTITION BY
                rent_event.id_tenant_prospect,
                rent_event.id_agent
            ORDER BY
                rent_event.ts_event ASC,
                rent_event.id_contract ASC
        ) AS contract_rank
    FROM
        datalake_rent_demand_events.rent_demand_events AS rent_event
    WHERE
        rent_event.id_event_type = 9
        AND rent_event.id_agent IS NOT NULL
        AND rent_event.id_contract IS NOT NULL
        AND rent_event.country_code = 'BR'
),
sale_invite_pair AS (
    SELECT DISTINCT
        CAST(invite.id_lead AS STRING) AS id_lead,
        CAST(invite.id_agent AS STRING) AS id_agent_data
    FROM
        datalake_ebdb_clean.agent_lead_referral AS invite
    WHERE
        invite.business_context = 'SALE'
        OR invite.business_context IS NULL
),
lead_has_sale_invite AS (
    SELECT DISTINCT
        sale_invite_pair.id_lead
    FROM
        sale_invite_pair
),
invite_with_other_tqc AS (
    SELECT DISTINCT
        invite.id AS id_lead_referral
    FROM
        datalake_ebdb_clean.agent_lead_referral AS invite
    INNER JOIN
        sale_tqc_offer
            ON CAST(invite.id_lead AS STRING) = CAST(sale_tqc_offer.id_buyer AS STRING)
            AND (
                sale_tqc_offer.id_agent_data IS NULL
                OR CAST(invite.id_agent AS STRING) <> CAST(sale_tqc_offer.id_agent_data AS STRING)
            )
    WHERE
        invite.business_context = 'SALE'
        OR invite.business_context IS NULL
),
sale_offer_without_tqc AS (
    SELECT DISTINCT
        CAST(sale_offer.id_buyer AS STRING) AS id_lead
    FROM
        datalake_sale_offer.sale_offer AS sale_offer
    LEFT JOIN
        datalake_sale_offer_flows.offer_specialists AS offer_specialists
            ON sale_offer.id_offer = offer_specialists.id_offer
    WHERE
        sale_offer.id_buyer IS NOT NULL
        AND (
            offer_specialists.id_offer IS NULL
            OR offer_specialists.id_user_agent_lead_referral IS NULL
        )
),
rent_offer_submitted AS (
    SELECT DISTINCT
        CAST(rent_event.id_tenant_prospect AS STRING) AS id_lead
    FROM
        datalake_rent_demand_events.rent_demand_events AS rent_event
    WHERE
        rent_event.id_event_type = 3
        AND rent_event.id_tenant_prospect IS NOT NULL
        AND rent_event.country_code = 'BR'
),
rent_offer_attributed_to_agent AS (
    SELECT DISTINCT
        CAST(rent_event.id_tenant_prospect AS STRING) AS id_lead,
        CAST(rent_event.id_agent AS STRING) AS id_user_agent
    FROM
        datalake_rent_demand_events.rent_demand_events AS rent_event
    WHERE
        rent_event.id_event_type = 3
        AND rent_event.id_tenant_prospect IS NOT NULL
        AND rent_event.id_agent IS NOT NULL
        AND rent_event.country_code = 'BR'
),
invite_spine AS (
    SELECT
        CONCAT('invite_', CAST(invite.id AS STRING)) AS id_demand_referral,
        invite.id AS id_lead_referral,
        invite.id_agent AS id_agent_data,
        COALESCE(accreditation.id_user, referrer_user.id) AS id_user_referrer,
        accreditation.id_agent,
        accreditation.id_partner,
        invite.id_lead,
        sale_tqc_offer.id_offer AS id_sale_offer,
        rent_contract_signed.id_rent_offer,
        rent_contract_signed.id_rent_contract,
        COALESCE(sale_tqc_offer.id_house, rent_contract_signed.id_house) AS id_house,
        sale_tqc_offer.id_user_agent,
        sale_tqc_offer.id_user_consultant AS id_user_negotiation_executive,
        sale_tqc_offer.id_user_team_lead AS id_user_associated_executive,
        accreditation.id_negotiation_executive_user,
        sale_tqc_offer.id_agent_lead_referral AS id_specialist_referrer,
        accreditation.uuid_agent,
        COALESCE(accreditation.uuid_person, referrer_user.uuid_person) AS uuid_person,
        CASE
            WHEN invite.business_context = 'RENT' THEN 'TQA'
            ELSE 'TQC'
        END AS sourcing_channel,
        CASE
            WHEN sale_tqc_offer.id_offer IS NOT NULL
                OR rent_contract_signed.id_rent_contract IS NOT NULL THEN 'INVITE_AND_OFFER'
            ELSE 'INVITE_ONLY'
        END AS attribution_source,
        invite.business_context,
        invite.origin,
        invite.status AS referral_status,
        COALESCE(
            NULLIF(
                CONCAT_WS(
                    '_',
                    CASE
                        WHEN sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_agent THEN 'AGENT'
                    END,
                    CASE
                        WHEN sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_consultant THEN 'NEGOTIATION_EXECUTIVE'
                    END,
                    CASE
                        WHEN sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_team_lead THEN 'ASSOCIATED_EXECUTIVE'
                    END
                ),
                ''
            ),
            CASE
                WHEN sale_tqc_offer.id_offer IS NOT NULL THEN 'OTHER'
            END
        ) AS referral_type,
        accreditation.affiliation_type,
        accreditation.status AS agent_status,
        accreditation.profile AS agent_profile,
        accreditation.is_allow_demand_acquisition,
        accreditation.is_allow_demand_sale,
        accreditation.is_allow_demand_rent,
        referrer_user.is_active AS is_referrer_active,
        TRUE AS has_invite,
        COALESCE(invite_with_other_tqc.id_lead_referral IS NOT NULL, FALSE) AS has_tqc_offer_for_lead_other_agent,
        FALSE AS has_other_agent_invite_for_lead,
        CASE
            WHEN invite.business_context = 'RENT'
                THEN COALESCE(
                    rent_offer_submitted.id_lead IS NOT NULL
                    AND rent_offer_attributed_to_agent.id_lead IS NULL,
                    FALSE
                )
            ELSE COALESCE(sale_offer_without_tqc.id_lead IS NOT NULL, FALSE)
        END AS has_unattributed_same_context_offer,
        COALESCE(invite.status = 'CONFIRMED', FALSE) AS is_confirmed,
        COALESCE(invite.status = 'NOT_ELIGIBLE', FALSE) AS is_not_eligible,
        COALESCE(sale_tqc_offer.id_offer IS NOT NULL, FALSE) AS is_converted_to_sale_offer,
        COALESCE(rent_contract_signed.id_rent_contract IS NOT NULL, FALSE) AS is_converted_to_rent_contract,
        COALESCE(
            sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_agent,
            FALSE
        ) AS is_agent_referral,
        COALESCE(
            sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_consultant,
            FALSE
        ) AS is_negotiation_executive_referral,
        COALESCE(
            sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_team_lead,
            FALSE
        ) AS is_associated_executive_referral,
        DATE(COALESCE(invite.ts_created, invite.ts_updated)) AS dt_invite,
        DATE(sale_tqc_offer.ts_offer_submitted) AS dt_sale_offer,
        DATE(rent_contract_signed.ts_rent_contract_signed) AS dt_rent_contract_signed,
        invite.ts_created AS ts_invite_created,
        invite.ts_updated AS ts_invite_updated,
        sale_tqc_offer.ts_offer_submitted AS ts_sale_offer_submitted,
        sale_tqc_offer.ts_agent_lead_referral_updated,
        rent_contract_signed.ts_rent_contract_signed,
        YEAR(DATE(COALESCE(invite.ts_created, invite.ts_updated))) AS year,
        MONTH(DATE(COALESCE(invite.ts_created, invite.ts_updated))) AS month,
        DAY(DATE(COALESCE(invite.ts_created, invite.ts_updated))) AS day
    FROM
        datalake_ebdb_clean.agent_lead_referral AS invite
    LEFT JOIN
        datalake_agent_accreditation.agent AS accreditation
            ON CAST(invite.id_agent AS STRING) = CAST(accreditation.id_agent_data AS STRING)
    LEFT JOIN
        referrer_user
            ON CAST(invite.id_agent AS STRING) = CAST(referrer_user.id_agent AS STRING)
            AND referrer_user.user_rank = 1
    LEFT JOIN
        sale_tqc_offer
            ON CAST(invite.id_lead AS STRING) = CAST(sale_tqc_offer.id_buyer AS STRING)
            AND sale_tqc_offer.id_agent_data IS NOT NULL
            AND CAST(invite.id_agent AS STRING) = CAST(sale_tqc_offer.id_agent_data AS STRING)
            AND sale_tqc_offer.offer_rank = 1
            AND (
                invite.business_context = 'SALE'
                OR invite.business_context IS NULL
            )
    LEFT JOIN
        rent_contract_signed
            ON CAST(invite.id_lead AS STRING) = CAST(rent_contract_signed.id_lead AS STRING)
            AND CAST(COALESCE(accreditation.id_user, referrer_user.id) AS STRING) = CAST(rent_contract_signed.id_user_agent AS STRING)
            AND rent_contract_signed.contract_rank = 1
            AND invite.business_context = 'RENT'
    LEFT JOIN
        invite_with_other_tqc
            ON invite.id = invite_with_other_tqc.id_lead_referral
    LEFT JOIN
        sale_offer_without_tqc
            ON CAST(invite.id_lead AS STRING) = sale_offer_without_tqc.id_lead
            AND (
                invite.business_context = 'SALE'
                OR invite.business_context IS NULL
            )
    LEFT JOIN
        rent_offer_submitted
            ON CAST(invite.id_lead AS STRING) = rent_offer_submitted.id_lead
            AND invite.business_context = 'RENT'
    LEFT JOIN
        rent_offer_attributed_to_agent
            ON CAST(invite.id_lead AS STRING) = rent_offer_attributed_to_agent.id_lead
            AND CAST(COALESCE(accreditation.id_user, referrer_user.id) AS STRING) = rent_offer_attributed_to_agent.id_user_agent
            AND invite.business_context = 'RENT'
),
offer_only_spine AS (
    SELECT
        CONCAT('sale_offer_', CAST(sale_tqc_offer.id_offer AS STRING)) AS id_demand_referral,
        CAST(NULL AS BIGINT) AS id_lead_referral,
        sale_tqc_offer.id_agent_data,
        COALESCE(accreditation.id_user, sale_tqc_offer.id_user_agent_lead_referral) AS id_user_referrer,
        accreditation.id_agent,
        accreditation.id_partner,
        sale_tqc_offer.id_buyer AS id_lead,
        sale_tqc_offer.id_offer AS id_sale_offer,
        CAST(NULL AS BIGINT) AS id_rent_offer,
        CAST(NULL AS BIGINT) AS id_rent_contract,
        sale_tqc_offer.id_house,
        sale_tqc_offer.id_user_agent,
        sale_tqc_offer.id_user_consultant AS id_user_negotiation_executive,
        sale_tqc_offer.id_user_team_lead AS id_user_associated_executive,
        accreditation.id_negotiation_executive_user,
        sale_tqc_offer.id_agent_lead_referral AS id_specialist_referrer,
        accreditation.uuid_agent,
        COALESCE(accreditation.uuid_person, referrer_user.uuid_person) AS uuid_person,
        'TQC' AS sourcing_channel,
        'OFFER_ONLY' AS attribution_source,
        'SALE' AS business_context,
        CAST(NULL AS STRING) AS origin,
        'NO_INVITE' AS referral_status,
        COALESCE(
            NULLIF(
                CONCAT_WS(
                    '_',
                    CASE
                        WHEN sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_agent THEN 'AGENT'
                    END,
                    CASE
                        WHEN sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_consultant THEN 'NEGOTIATION_EXECUTIVE'
                    END,
                    CASE
                        WHEN sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_team_lead THEN 'ASSOCIATED_EXECUTIVE'
                    END
                ),
                ''
            ),
            'OTHER'
        ) AS referral_type,
        accreditation.affiliation_type,
        accreditation.status AS agent_status,
        accreditation.profile AS agent_profile,
        accreditation.is_allow_demand_acquisition,
        accreditation.is_allow_demand_sale,
        accreditation.is_allow_demand_rent,
        referrer_user.is_active AS is_referrer_active,
        FALSE AS has_invite,
        FALSE AS has_tqc_offer_for_lead_other_agent,
        COALESCE(lead_has_sale_invite.id_lead IS NOT NULL, FALSE) AS has_other_agent_invite_for_lead,
        FALSE AS has_unattributed_same_context_offer,
        FALSE AS is_confirmed,
        FALSE AS is_not_eligible,
        TRUE AS is_converted_to_sale_offer,
        FALSE AS is_converted_to_rent_contract,
        COALESCE(
            sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_agent,
            FALSE
        ) AS is_agent_referral,
        COALESCE(
            sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_consultant,
            FALSE
        ) AS is_negotiation_executive_referral,
        COALESCE(
            sale_tqc_offer.id_user_agent_lead_referral = sale_tqc_offer.id_user_team_lead,
            FALSE
        ) AS is_associated_executive_referral,
        CAST(NULL AS DATE) AS dt_invite,
        DATE(sale_tqc_offer.ts_offer_submitted) AS dt_sale_offer,
        CAST(NULL AS DATE) AS dt_rent_contract_signed,
        CAST(NULL AS TIMESTAMP) AS ts_invite_created,
        CAST(NULL AS TIMESTAMP) AS ts_invite_updated,
        sale_tqc_offer.ts_offer_submitted AS ts_sale_offer_submitted,
        sale_tqc_offer.ts_agent_lead_referral_updated,
        CAST(NULL AS TIMESTAMP) AS ts_rent_contract_signed,
        YEAR(DATE(sale_tqc_offer.ts_offer_submitted)) AS year,
        MONTH(DATE(sale_tqc_offer.ts_offer_submitted)) AS month,
        DAY(DATE(sale_tqc_offer.ts_offer_submitted)) AS day
    FROM
        sale_tqc_offer
    LEFT JOIN
        sale_invite_pair
            ON CAST(sale_tqc_offer.id_buyer AS STRING) = sale_invite_pair.id_lead
            AND sale_tqc_offer.id_agent_data IS NOT NULL
            AND CAST(sale_tqc_offer.id_agent_data AS STRING) = sale_invite_pair.id_agent_data
    LEFT JOIN
        lead_has_sale_invite
            ON CAST(sale_tqc_offer.id_buyer AS STRING) = lead_has_sale_invite.id_lead
    LEFT JOIN
        datalake_agent_accreditation.agent AS accreditation
            ON sale_tqc_offer.id_user_agent_lead_referral = accreditation.id_user
    LEFT JOIN
        referrer_user
            ON sale_tqc_offer.id_agent_data IS NOT NULL
            AND CAST(sale_tqc_offer.id_agent_data AS STRING) = CAST(referrer_user.id_agent AS STRING)
            AND referrer_user.user_rank = 1
    WHERE
        sale_invite_pair.id_lead IS NULL
)
SELECT
    invite_spine.id_demand_referral,
    invite_spine.id_lead_referral,
    invite_spine.id_agent_data,
    invite_spine.id_user_referrer,
    invite_spine.id_agent,
    invite_spine.id_partner,
    invite_spine.id_lead,
    invite_spine.id_sale_offer,
    invite_spine.id_rent_offer,
    invite_spine.id_rent_contract,
    invite_spine.id_house,
    invite_spine.id_user_agent,
    invite_spine.id_user_negotiation_executive,
    invite_spine.id_user_associated_executive,
    invite_spine.id_negotiation_executive_user,
    invite_spine.id_specialist_referrer,
    invite_spine.uuid_agent,
    invite_spine.uuid_person,
    invite_spine.sourcing_channel,
    invite_spine.attribution_source,
    invite_spine.business_context,
    invite_spine.origin,
    invite_spine.referral_status,
    invite_spine.referral_type,
    invite_spine.affiliation_type,
    invite_spine.agent_status,
    invite_spine.agent_profile,
    invite_spine.is_allow_demand_acquisition,
    invite_spine.is_allow_demand_sale,
    invite_spine.is_allow_demand_rent,
    invite_spine.is_referrer_active,
    invite_spine.has_invite,
    invite_spine.has_tqc_offer_for_lead_other_agent,
    invite_spine.has_other_agent_invite_for_lead,
    invite_spine.has_unattributed_same_context_offer,
    invite_spine.is_confirmed,
    invite_spine.is_not_eligible,
    invite_spine.is_converted_to_sale_offer,
    invite_spine.is_converted_to_rent_contract,
    invite_spine.is_agent_referral,
    invite_spine.is_negotiation_executive_referral,
    invite_spine.is_associated_executive_referral,
    invite_spine.dt_invite,
    invite_spine.dt_sale_offer,
    invite_spine.dt_rent_contract_signed,
    invite_spine.ts_invite_created,
    invite_spine.ts_invite_updated,
    invite_spine.ts_sale_offer_submitted,
    invite_spine.ts_agent_lead_referral_updated,
    invite_spine.ts_rent_contract_signed,
    invite_spine.year,
    invite_spine.month,
    invite_spine.day
FROM
    invite_spine
UNION ALL
SELECT
    offer_only_spine.id_demand_referral,
    offer_only_spine.id_lead_referral,
    offer_only_spine.id_agent_data,
    offer_only_spine.id_user_referrer,
    offer_only_spine.id_agent,
    offer_only_spine.id_partner,
    offer_only_spine.id_lead,
    offer_only_spine.id_sale_offer,
    offer_only_spine.id_rent_offer,
    offer_only_spine.id_rent_contract,
    offer_only_spine.id_house,
    offer_only_spine.id_user_agent,
    offer_only_spine.id_user_negotiation_executive,
    offer_only_spine.id_user_associated_executive,
    offer_only_spine.id_negotiation_executive_user,
    offer_only_spine.id_specialist_referrer,
    offer_only_spine.uuid_agent,
    offer_only_spine.uuid_person,
    offer_only_spine.sourcing_channel,
    offer_only_spine.attribution_source,
    offer_only_spine.business_context,
    offer_only_spine.origin,
    offer_only_spine.referral_status,
    offer_only_spine.referral_type,
    offer_only_spine.affiliation_type,
    offer_only_spine.agent_status,
    offer_only_spine.agent_profile,
    offer_only_spine.is_allow_demand_acquisition,
    offer_only_spine.is_allow_demand_sale,
    offer_only_spine.is_allow_demand_rent,
    offer_only_spine.is_referrer_active,
    offer_only_spine.has_invite,
    offer_only_spine.has_tqc_offer_for_lead_other_agent,
    offer_only_spine.has_other_agent_invite_for_lead,
    offer_only_spine.has_unattributed_same_context_offer,
    offer_only_spine.is_confirmed,
    offer_only_spine.is_not_eligible,
    offer_only_spine.is_converted_to_sale_offer,
    offer_only_spine.is_converted_to_rent_contract,
    offer_only_spine.is_agent_referral,
    offer_only_spine.is_negotiation_executive_referral,
    offer_only_spine.is_associated_executive_referral,
    offer_only_spine.dt_invite,
    offer_only_spine.dt_sale_offer,
    offer_only_spine.dt_rent_contract_signed,
    offer_only_spine.ts_invite_created,
    offer_only_spine.ts_invite_updated,
    offer_only_spine.ts_sale_offer_submitted,
    offer_only_spine.ts_agent_lead_referral_updated,
    offer_only_spine.ts_rent_contract_signed,
    offer_only_spine.year,
    offer_only_spine.month,
    offer_only_spine.day
FROM
    offer_only_spine
