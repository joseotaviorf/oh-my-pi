WITH merged_companies_aux AS (
    SELECT
        ids_merged_companies
    FROM
        datalake_hubspot.company_history
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_company ORDER BY ts_updated DESC) = 1
),
merged_companies AS (
    SELECT
        EXPLODE(ids_merged_companies) AS id_merged_company
    FROM
        merged_companies_aux
),
hubspot_companies AS (
    SELECT
        id_company,
        document,
        cnpj,
        rfc,
        ts_updated,
        LAST(sale_lead_status)
        OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS current_sale_status,
        LAST(rent_lead_status)
        OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS current_rent_status,
        LAST(tag_real_estate_agency)
        OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS current_tag,
        LAST(is_archived)
        OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS is_currently_archived
    FROM
        datalake_hubspot.company_history
),
-- We're repeating part of the logic applied to datalake_company.company
-- We can't use it directly here because it would delay the start of the query,
-- impacting enrich_ebdb_listing
listing_ownership AS (
    SELECT
        hlr.id_related AS uuid_company,
        COUNT(DISTINCT lbc.id_house) AS houses_currently_owned
    FROM
        datalake_ebdb_clean.house_listing_relation AS hlr
    JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id = hlr.id_listing_business_context
    WHERE
        hlr.related_as = 'LISTING_OWNER'
        AND hlr.source_type = 'COMPANY_REF'
    GROUP BY 1
),
company_document AS (
    SELECT
        COALESCE(c.uuid_company, d.uuid_company) AS uuid_company,
        CASE
            WHEN a.country IN ('Brasil', 'Brazil', 'BR')
            OR a.country IS NULL THEN NULLIF(REGEXP_REPLACE(identification_number, '[^0-9]', ''), '')
        END AS cnpj,
        CASE
            WHEN a.country IN ('México', 'Mexico', 'MX') THEN NULLIF(REGEXP_REPLACE(identification_number, '[^0-9A-Za-z]', ''), '')
        END AS rfc,
        NULLIF(REGEXP_REPLACE(identification_number, '[^0-9A-Za-z]', ''), '') AS document,
        c.status AS company_status,
        CASE d.status
            WHEN 'ACTIVE' THEN 0
            ELSE 1
        END AS document_status_preference
    FROM
        datalake_company_clean.document AS d
    LEFT JOIN
        datalake_company_clean.company_document AS cd
            ON cd.id_document = d.id
    LEFT JOIN
        datalake_company_clean.company AS c
            ON c.id = cd.id_company
    LEFT JOIN
        datalake_company_clean.address AS a
            ON c.uuid_company = a.uuid_company
    WHERE
        document_type IN ('CNPJ', 'RFC')
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY c.uuid_company ORDER BY document_status_preference, d.ts_updated DESC) = 1
),
-- Select the best match for each hubspot company.
company_matches_aux AS (
    SELECT
        cd.uuid_company,
        ch.id_company AS id_company_hubspot,
        mc.id_merged_company,
        ch.current_tag,
        ch.is_currently_archived,
        (
            ch.current_sale_status IN ('Membro', 'Parceiro', 'Em processo tombamento')
            OR ch.current_rent_status IN ('Membro', 'Parceiro', 'Em processo tombamento')
        ) AS is_current_hubspot_member,
        ch.ts_updated AS ts_hubspot_updated
    FROM
        company_document AS cd
    LEFT JOIN
        listing_ownership AS lo
            ON lo.uuid_company = cd.uuid_company
    JOIN
        hubspot_companies AS ch
            ON cd.document = ch.document
            OR cd.cnpj = ch.cnpj
            OR cd.rfc = ch.rfc
    LEFT JOIN
        merged_companies AS mc
            ON ch.id_company = mc.id_merged_company
    QUALIFY
        ROW_NUMBER() OVER (
        PARTITION BY
            ch.id_company
        ORDER BY
            lo.houses_currently_owned DESC, -- First, companies with houses
            cd.company_status IS NOT DISTINCT FROM 'ACTIVE' DESC -- Then, active companies
        ) = 1
),
-- Sometimes multiple hubspot companies match the same uuid_company. Then, here we select the best match for each uuid_company
company_matches AS (
    SELECT
        uuid_company,
        id_company_hubspot
    FROM
        company_matches_aux
    QUALIFY
        ROW_NUMBER() OVER (
        PARTITION BY
            uuid_company
        ORDER BY
            NOT is_currently_archived AND id_merged_company IS NULL DESC, -- First, not archived nor merged
            is_current_hubspot_member DESC, -- Then, the ones that are currently members
            current_tag IS NOT NULL DESC, -- Then, the ones with tags
            ts_hubspot_updated DESC -- Otherwise, most recent
        ) = 1
)
SELECT
    ch.id_company,
    cm.uuid_company,
    cc.id_contact AS id_deciding_contact,
    ch.id_hubspot_owner,
    ch.id_hubspot_team,
    ch.id_parent_company,
    ch.ids_merged_companies,
    ch.fields_of_business,
    ch.address,
    ch.zip_code,
    ch.city,
    ch.state,
    ch.country,
    ch.country_code,
    ch.domain,
    ch.e_mail,
    ch.hs_analytics_source,
    ch.hs_analytics_source_data_1,
    ch.hs_analytics_source_data_2,
    ch.industry,
    ch.inside_sales,
    ch.life_cycle_stage,
    ch.mkt_campain,
    ch.mkt_channel,
    ch.mkt_content,
    ch.mkt_medium,
    ch.mkt_origin,
    ch.mkt_source,
    ch.discard_reason,
    ch.unified_discard_reasons,
    ch.name,
    ch.tag_real_estate_agency,
    ch.extracted_3p_tag,
    ch.member_type,
    ch.member_category,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, member_category will be deprecated and we will remove the row above
    ch.sale_member_category,
    ch.rent_member_category,
    ch.company_cluster,
    ch.member_category_history,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, member_category_history will be deprecated and we will remove the row above
    ch.sale_member_category_history,
    ch.rent_member_category_history,
    ch.company_cluster_history,
    ch.lead_origin,
    ch.phone,
    ch.partnership_type,
    ch.first_conversion_event_name,
    ch.hs_analytics_first_touch_converting_campaign,
    ch.crm,
    ch.partner_agencies,
    ch.advertising_portals,
    ch.rental_guarantee_solutions,
    ch.real_estate_agency_focus,
    ch.financing_banks,
    ch.document,
    ch.cnpj,
    ch.rfc,
    ch.creci,
    ch.products_of_interest,
    CASE
        WHEN mc.id_merged_company IS NOT NULL OR ch.is_archived THEN 'Archived'
        ELSE ch.lead_status
    END AS lead_status,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, lead_status will be deprecated and we will remove the row above
    CASE
        WHEN mc.id_merged_company IS NOT NULL OR ch.is_archived THEN 'Archived'
        ELSE ch.sale_lead_status
    END AS sale_lead_status,
    CASE
        WHEN mc.id_merged_company IS NOT NULL OR ch.is_archived THEN 'Archived'
        ELSE ch.rent_lead_status
    END AS rent_lead_status,
    ch.lead_status_history,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, lead_status will be deprecated and we will remove the row above
    ch.sale_lead_status_history,
    ch.rent_lead_status_history,
    ch.report_link,
    ch.inventory_profile,
    ch.cluster_performance,
    ch.responsible_secretary,
    ch.responsible_supply_expert,
    ch.responsible_demand_expert,
    ch.responsible_operations_supply,
    ch.average_monthly_ccvs,
    ch.average_monthly_ccvs_outside_rede_quintoandar,
    ch.num_properties_for_sale_farming_qualification,
    ch.num_properties_for_rent_farming_qualification,
    ch.num_real_estate_agents_farming_qualification,
    ch.num_managers_farming_qualification,
    ch.average_sale_property_ticket_farming_qualification,
    ch.average_rent_property_ticket_farming_qualification,
    ch.num_associated_deals,
    ch.num_associated_contacts,
    ch.monthly_average_new_rental_contracts,
    ch.num_managers,
    ch.num_managed_properties,
    ch.num_monthly_leads,
    ch.average_sale_property_ticket,
    ch.average_rent_property_ticket,
    ch.monthly_repayment_volume_in_real,
    ch.monthly_sale_volume_in_real,
    ch.num_real_estate_agents,
    ch.num_properties_for_sale,
    ch.num_properties_for_rent,
    COALESCE(
        ARRAY_CONTAINS(sale_lead_status_history.value, 'Membro')
        OR ARRAY_CONTAINS(sale_lead_status_history.value, 'Parceiro'),
        FALSE
    ) AS has_been_sale_member,
    COALESCE(
        ARRAY_CONTAINS(rent_lead_status_history.value, 'Membro')
        OR ARRAY_CONTAINS(rent_lead_status_history.value, 'Parceiro'),
        FALSE
    ) AS has_been_rent_member,
    ch.has_crm,
    ch.has_property_advertisement_online,
    ch.is_correspondent_bank,
    ch.is_lost,
    ch.has_financing,
    ch.is_for_sale,
    ch.is_for_rent,
    ch.is_flagged_as_leadgen,
    ch.has_partnerships_with_other_agencies,
    ch.is_natural_person,
    ch.is_juridical_person,
    mc.id_merged_company IS NOT NULL OR ch.is_archived AS is_archived,
    mc.id_merged_company IS NOT NULL AS is_merged_into_other_company,
    ch.ts_first_conversion,
    ch.ts_recent_deal_close,
    ch.ts_hubspot_owner_assigned,
    ch.ts_last_logged_call,
    ch.ts_notes_last_updated,
    ch.ts_live_demand_only,
    IF(mc.id_merged_company IS NOT NULL, ch.ts_updated, ch.ts_archived) AS ts_archived,
    ch.ts_created,
    ch.ts_updated,
    ch.year,
    ch.month,
    ch.day
FROM
    datalake_hubspot.company_history AS ch
LEFT JOIN
    company_matches AS cm
        ON ch.id_company = cm.id_company_hubspot
LEFT JOIN
    merged_companies AS mc
        ON ch.id_company = mc.id_merged_company
LEFT JOIN
    datalake_hubspot.company_contact AS cc
        ON cc.id_company = ch.id_company
        AND cc.contact_association_type = 'DECIDING_CONTACT'
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY ch.id_company ORDER BY ch.ts_updated DESC) = 1