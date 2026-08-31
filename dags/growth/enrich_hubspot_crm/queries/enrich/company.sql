WITH company_history_ranked AS (
    SELECT
        id_company,
        ids_merged_companies,
        ts_updated,
        ROW_NUMBER() OVER (PARTITION BY id_company ORDER BY ts_updated DESC) AS rn
    FROM
        datalake_hubspot.company_history
),
merged_companies_aux AS (
    SELECT
        ids_merged_companies
    FROM
        company_history_ranked
    WHERE
        rn = 1
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
company_document_candidates AS (
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
        END AS document_status_preference,
        ROW_NUMBER() OVER (
            PARTITION BY
                c.uuid_company
            ORDER BY
                CASE d.status WHEN 'ACTIVE' THEN 0 ELSE 1 END,
                d.ts_updated DESC
        ) AS rn
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
),
company_document AS (
    SELECT
        uuid_company,
        cnpj,
        rfc,
        document,
        company_status,
        document_status_preference
    FROM
        company_document_candidates
    WHERE
        rn = 1
),
-- Match HubSpot companies on document, CNPJ, or RFC as UNION of equi-joins
-- (not OR in ON) so Spark can hash-join on EMR.
company_hubspot_key_matches AS (
    SELECT
        cd.uuid_company,
        cd.company_status,
        ch.id_company,
        ch.current_tag,
        ch.is_currently_archived,
        ch.current_sale_status,
        ch.current_rent_status,
        ch.ts_updated
    FROM
        company_document AS cd
    INNER JOIN
        hubspot_companies AS ch
            ON cd.document = ch.document

    UNION

    SELECT
        cd.uuid_company,
        cd.company_status,
        ch.id_company,
        ch.current_tag,
        ch.is_currently_archived,
        ch.current_sale_status,
        ch.current_rent_status,
        ch.ts_updated
    FROM
        company_document AS cd
    INNER JOIN
        hubspot_companies AS ch
            ON cd.cnpj = ch.cnpj

    UNION

    SELECT
        cd.uuid_company,
        cd.company_status,
        ch.id_company,
        ch.current_tag,
        ch.is_currently_archived,
        ch.current_sale_status,
        ch.current_rent_status,
        ch.ts_updated
    FROM
        company_document AS cd
    INNER JOIN
        hubspot_companies AS ch
            ON cd.rfc = ch.rfc
),
-- Select the best match for each hubspot company.
company_matches_candidates AS (
    SELECT
        km.uuid_company,
        km.id_company AS id_company_hubspot,
        mc.id_merged_company,
        km.current_tag,
        km.is_currently_archived,
        (
            km.current_sale_status IN ('Membro', 'Parceiro', 'Em processo tombamento')
            OR km.current_rent_status IN ('Membro', 'Parceiro', 'Em processo tombamento')
        ) AS is_current_hubspot_member,
        km.ts_updated AS ts_hubspot_updated,
        ROW_NUMBER() OVER (
        PARTITION BY
            km.id_company
        ORDER BY
            lo.houses_currently_owned DESC, -- First, companies with houses
            km.company_status IS NOT DISTINCT FROM 'ACTIVE' DESC -- Then, active companies
        ) AS rn
    FROM
        company_hubspot_key_matches AS km
    LEFT JOIN
        listing_ownership AS lo
            ON lo.uuid_company = km.uuid_company
    LEFT JOIN
        merged_companies AS mc
            ON km.id_company = mc.id_merged_company
),
company_matches_aux AS (
    SELECT
        uuid_company,
        id_company_hubspot,
        id_merged_company,
        current_tag,
        is_currently_archived,
        is_current_hubspot_member,
        ts_hubspot_updated
    FROM
        company_matches_candidates
    WHERE
        rn = 1
),
-- Sometimes multiple hubspot companies match the same uuid_company. Then, here we select the best match for each uuid_company
company_matches_ranked AS (
    SELECT
        uuid_company,
        id_company_hubspot,
        ROW_NUMBER() OVER (
        PARTITION BY
            uuid_company
        ORDER BY
            NOT is_currently_archived AND id_merged_company IS NULL DESC, -- First, not archived nor merged
            is_current_hubspot_member DESC, -- Then, the ones that are currently members
            current_tag IS NOT NULL DESC, -- Then, the ones with tags
            ts_hubspot_updated DESC -- Otherwise, most recent
        ) AS rn
    FROM
        company_matches_aux
),
company_matches AS (
    SELECT
        uuid_company,
        id_company_hubspot
    FROM
        company_matches_ranked
    WHERE
        rn = 1
),
deduped_companies AS (
    SELECT
        ch.id_company,
        cm.uuid_company,
        cc.id_contact AS id_deciding_contact,
        ch.id_hubspot_owner,
        ch.id_account_manager_for_sale,
        ch.id_account_manager_for_rent,
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
        ch.cnpj_unique,
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
        TRUE AS has_3p_access_control,
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
        ch.day,
        ROW_NUMBER() OVER(PARTITION BY ch.id_company ORDER BY ch.ts_updated DESC) AS rn
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
)
SELECT
    id_company,
    uuid_company,
    id_deciding_contact,
    id_hubspot_owner,
    id_account_manager_for_sale,
    id_account_manager_for_rent,
    id_hubspot_team,
    id_parent_company,
    ids_merged_companies,
    fields_of_business,
    address,
    zip_code,
    city,
    state,
    country,
    country_code,
    domain,
    e_mail,
    hs_analytics_source,
    hs_analytics_source_data_1,
    hs_analytics_source_data_2,
    industry,
    inside_sales,
    life_cycle_stage,
    mkt_campain,
    mkt_channel,
    mkt_content,
    mkt_medium,
    mkt_origin,
    mkt_source,
    discard_reason,
    unified_discard_reasons,
    name,
    tag_real_estate_agency,
    extracted_3p_tag,
    member_type,
    member_category,
    sale_member_category,
    rent_member_category,
    company_cluster,
    member_category_history,
    sale_member_category_history,
    rent_member_category_history,
    company_cluster_history,
    lead_origin,
    phone,
    partnership_type,
    first_conversion_event_name,
    hs_analytics_first_touch_converting_campaign,
    crm,
    partner_agencies,
    advertising_portals,
    rental_guarantee_solutions,
    real_estate_agency_focus,
    financing_banks,
    document,
    cnpj,
    cnpj_unique,
    rfc,
    creci,
    products_of_interest,
    lead_status,
    sale_lead_status,
    rent_lead_status,
    lead_status_history,
    sale_lead_status_history,
    rent_lead_status_history,
    report_link,
    inventory_profile,
    cluster_performance,
    responsible_secretary,
    responsible_supply_expert,
    responsible_demand_expert,
    responsible_operations_supply,
    average_monthly_ccvs,
    average_monthly_ccvs_outside_rede_quintoandar,
    num_properties_for_sale_farming_qualification,
    num_properties_for_rent_farming_qualification,
    num_real_estate_agents_farming_qualification,
    num_managers_farming_qualification,
    average_sale_property_ticket_farming_qualification,
    average_rent_property_ticket_farming_qualification,
    num_associated_deals,
    num_associated_contacts,
    monthly_average_new_rental_contracts,
    num_managers,
    num_managed_properties,
    num_monthly_leads,
    average_sale_property_ticket,
    average_rent_property_ticket,
    monthly_repayment_volume_in_real,
    monthly_sale_volume_in_real,
    num_real_estate_agents,
    num_properties_for_sale,
    num_properties_for_rent,
    has_been_sale_member,
    has_been_rent_member,
    has_crm,
    has_property_advertisement_online,
    is_correspondent_bank,
    is_lost,
    has_financing,
    is_for_sale,
    is_for_rent,
    is_flagged_as_leadgen,
    has_partnerships_with_other_agencies,
    is_natural_person,
    is_juridical_person,
    is_archived,
    is_merged_into_other_company,
    has_3p_access_control,
    ts_first_conversion,
    ts_recent_deal_close,
    ts_hubspot_owner_assigned,
    ts_last_logged_call,
    ts_notes_last_updated,
    ts_live_demand_only,
    ts_archived,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    deduped_companies
WHERE
    rn = 1
