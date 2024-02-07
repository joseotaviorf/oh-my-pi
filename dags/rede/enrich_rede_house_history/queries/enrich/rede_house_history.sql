WITH extracted_partner_tags AS (
    SELECT
        ch.id_company,
        ch.tag_real_estate_agency AS tag,
        ch.extracted_3p_tag,
        c.extracted_3p_tag AS current_extracted_3p_tag,
        ch.name,
        ch.cnpj,
        ch.state AS partner_state,
        ROW_NUMBER() OVER(
        PARTITION BY
            REPLACE(UPPER(ch.extracted_3p_tag), ' ', '')
        ORDER BY
            ch.ts_updated
        DESC
        ) = 1 AS is_most_recent_for_tag,
        ROW_NUMBER() OVER ( -- Sometimes, more than one company in HubSpot is created with the same cnpj, so we need to deduplicate
            PARTITION BY
                ch.cnpj
            ORDER BY
                NOT c.is_archived DESC, -- First, not-archived companies have more preference
                c.lead_status IN ('Membro', 'Parceiro', 'Em processo tombamento') DESC, -- Then, the ones that are currently members
                c.extracted_3p_tag IS NOT NULL DESC, -- Then, the ones with tags
                ch.ts_updated DESC -- Otherwise, most recent
        ) = 1 AS is_most_recent_for_cnpj,
        ROW_NUMBER() OVER(PARTITION BY ch.id_company ORDER BY ch.ts_updated DESC) = 1 AS is_most_recent_for_company
    FROM
        datalake_hubspot.company_history AS ch
    JOIN
        datalake_hubspot.company AS c
            ON ch.id_company = c.id_company
    QUALIFY
        (is_most_recent_for_tag OR is_most_recent_for_cnpj OR is_most_recent_for_company)
        AND (tag IS NOT NULL OR ch.cnpj IS NOT NULL)
),
--- We're getting the most recent row in datalake_hubspot_clean.company for each tag and CNPJ.
--- Since they are merged, extracted_3p_tag only shows up if that row is the most recent company for the given tag. Same for the CNPJ.
partner_agencies AS (
  SELECT
    ept.id_company,
    ept.tag,
    CASE
      WHEN ept.is_most_recent_for_tag THEN ept.extracted_3p_tag
      ELSE NULL
    END AS extracted_3p_tag,
    CASE
      WHEN ept.is_most_recent_for_cnpj THEN ept.cnpj
      ELSE NULL
    END AS cnpj,
    COALESCE(ept.current_extracted_3p_tag, ept.extracted_3p_tag, ept.name) AS partner_3p_supply,
    ept.partner_state
  FROM
    extracted_partner_tags AS ept
),
house_history_aux AS (
    SELECT
        ha.id_house,
        ha.id_external,
        NULLIF(REGEXP_EXTRACT(REPLACE(ha.internal_admin_info, ' ', ''), r'\[3(?i:p)(?i:BH)?\-(.+?)\]'), '') AS extracted_tag,
        UPPER(ha.internal_admin_info) LIKE '%[3P%-%]%' AS is_3p_supply,
        COALESCE(internal_admin_info LIKE '%[3PBH-%]%', FALSE) AS has_3p_bh_in_tag,
        ure.ts_revision
    FROM
        datalake_ebdb_clean.house_aud AS ha
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON ha.rev = ure.id
    QUALIFY
        LAG(ha.internal_admin_info) OVER (PARTITION BY ha.id_house ORDER BY ha.rev) IS DISTINCT FROM ha.internal_admin_info
),
house_history AS (
    SELECT
        h.id_house,
        pa.id_company AS id_company_hubspot_extracted,
        COALESCE(
            pa.partner_3p_supply,
            h.extracted_tag,
            'Unknown'
        ) AS partner_3p_supply_extracted,
        COALESCE(is_3p_supply, FALSE) AS is_3p_supply,
        COALESCE(pa.partner_state = 'MG', has_3p_bh_in_tag, FALSE) AS is_3p_supply_bh,
        has_3p_bh_in_tag,
        l.id IS NOT NULL AS is_in_supply_processor,
        ts_revision AS ts_status_started
    FROM
        house_history_aux AS h
    LEFT JOIN
        partner_agencies AS pa
            ON UPPER(h.extracted_tag) IN (pa.cnpj, REPLACE(UPPER(pa.extracted_3p_tag), ' ', ''))
    LEFT JOIN
        datalake_brokers_supply_processor.lead_3p AS l
            ON h.id_external = l.uuid_lead
),
sale_united AS (
    (SELECT
        lbca.id_house,
        NULL::BIGINT AS id_company_hubspot_extracted,
        'LBC' AS source,
        NULL::STRING AS partner_3p_supply_extracted,
        lbca.ownership = 'THIRD_PARTY' AS is_3p_supply,
        NULL::BOOLEAN AS is_3p_supply_bh,
        NULL::BOOLEAN AS is_in_supply_processor,
        NULL::BOOLEAN AS has_3p_bh_in_tag,
        CASE -- Some migrations incorrectly set the revision timestamp to the year 2610. We're fixing them here.
            WHEN DATE(ure.ts_revision) = '2610-10-12' THEN '2022-10-25T23:53:18.764+0000'::TIMESTAMP
            WHEN DATE(ure.ts_revision) = '2610-10-07' THEN '2022-06-14T05:04:41.716+0000'::TIMESTAMP
            ELSE ure.ts_revision
        END AS ts_status_started
    FROM
        datalake_ebdb_clean.listing_business_context_aud AS lbca
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON lbca.rev = ure.id
    WHERE
        lbca.business_context = 'SALE'
        AND (lbca.ownership = 'THIRD_PARTY'
        OR(ure.ts_revision >= '2022-08-01' -- We won't trust revisions before this date, since the column ownership had just been added.
        AND DATE(ure.ts_revision) != '2610-10-07'))
    QUALIFY
        LAG(lbca.ownership) OVER (PARTITION BY lbca.id_listing_business_context ORDER BY lbca.rev) IS DISTINCT FROM lbca.ownership
    )
    UNION ALL
    SELECT
        id_house,
        id_company_hubspot_extracted,
        'H' AS source,
        partner_3p_supply_extracted,
        is_3p_supply,
        is_3p_supply_bh,
        is_in_supply_processor,
        has_3p_bh_in_tag,
        ts_status_started
    FROM
        house_history
),
sale_fetching_last AS (
    SELECT
        su.id_house,
        LAST(su.id_company_hubspot_extracted, TRUE) OVER (PARTITION BY su.id_house ORDER BY su.ts_status_started) AS id_company_hubspot_extracted,
        LAST(su.partner_3p_supply_extracted, TRUE) OVER (PARTITION BY su.id_house ORDER BY su.ts_status_started) AS partner_3p_supply_extracted,
        COALESCE(
            LAST( -- Before 2023, if the house was 3P, we can assume it was 3P ForSale. But after 2023, we can't, since the house could have been 3P ForRent.
                CASE WHEN su.source = 'H' AND (su.ts_status_started < '2023-01-01') THEN su.is_3p_supply END, TRUE
            ) OVER (
                PARTITION BY
                    su.id_house
                ORDER BY su.ts_status_started
            ),
            FALSE
        ) AS is_3p_supply_house_aud,
        LAST(
            CASE WHEN su.source = 'LBC' THEN su.is_3p_supply END, TRUE
        ) OVER (
            PARTITION BY
                su.id_house
            ORDER BY
                su.ts_status_started
        ) AS is_3p_supply_lbc_aud,
        LAST(su.is_3p_supply_bh, TRUE) OVER (PARTITION BY su.id_house ORDER BY su.ts_status_started) AS is_3p_supply_bh,
        LAST(su.is_in_supply_processor, TRUE) OVER (PARTITION BY su.id_house ORDER BY su.ts_status_started) AS is_in_supply_processor,
        LAST(su.has_3p_bh_in_tag, TRUE) OVER (PARTITION BY su.id_house ORDER BY su.ts_status_started) AS has_3p_bh_in_tag,
        su.ts_status_started
    FROM
        sale_united AS su
),
rent_united AS (
    (SELECT
        lbc.id_house,
        NULL::BIGINT AS id_company_hubspot_extracted,
        NULL::STRING AS partner_3p_supply_extracted,
        lrma.rental_administrator = 'THIRD_PARTY' AS is_3p_supply,
        NULL::BOOLEAN AS is_3p_supply_bh,
        ure.ts_revision AS ts_status_started
    FROM
        datalake_ebdb_clean.listing_rent_model_aud AS lrma
    JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id = lrma.id_listing_business_context
            AND lbc.business_context = 'RENT'
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON lrma.rev = ure.id
    QUALIFY
        LAG(lrma.rental_administrator) OVER (PARTITION BY lrma.id_listing_business_context ORDER BY lrma.rev) IS DISTINCT FROM lrma.rental_administrator)
    UNION ALL
    SELECT
        id_house,
        id_company_hubspot_extracted,
        partner_3p_supply_extracted,
        NULL AS is_3p_supply,
        is_3p_supply_bh,
        ts_status_started
    FROM
        house_history
),
rent_fetching_last AS (
    SELECT
        id_house,
        LAST(id_company_hubspot_extracted, TRUE) OVER (PARTITION BY id_house ORDER BY ts_status_started) AS id_company_hubspot_extracted,
        LAST(partner_3p_supply_extracted, TRUE) OVER (PARTITION BY id_house ORDER BY ts_status_started) AS partner_3p_supply_extracted,
        COALESCE(LAST(is_3p_supply, TRUE) OVER (
            PARTITION BY
                id_house
            ORDER BY
                ts_status_started
        ), FALSE) AS is_3p_supply,
        COALESCE(LAST(is_3p_supply_bh, TRUE) OVER (PARTITION BY id_house ORDER BY ts_status_started), FALSE) AS is_3p_supply_bh,
        ts_status_started
    FROM
        rent_united
),
sale_plus_rent AS (
    SELECT
        id_house,
        id_company_hubspot_extracted,
        'SALE' AS business_context,
        partner_3p_supply_extracted,
        -- Business rules to consider a listing Sale 3P supply:
        -- 3P BH was migrated incorrectly to the ownership column, so we will consider the tag instead
        -- We prioritize whatever came from listing_business_context, and then house
        -- If the house was inputed manually, we will consider the tag (until 2023)
        (
            has_3p_bh_in_tag
            OR COALESCE(is_3p_supply_lbc_aud, is_3p_supply_house_aud)
            OR (NOT is_in_supply_processor AND is_3p_supply_house_aud AND ts_status_started < '2023-01-01')
        ) AS is_3p_supply,
        is_3p_supply_bh,
        ts_status_started
    FROM
        sale_fetching_last
    UNION ALL
    SELECT
        id_house,
        id_company_hubspot_extracted,
        'RENT' AS business_context,
        partner_3p_supply_extracted,
        is_3p_supply,
        is_3p_supply_bh,
        ts_status_started
    FROM
        rent_fetching_last
),
add_status_changes AS (
    SELECT
        id_house,
        IF(is_3p_supply, id_company_hubspot_extracted, NULL) AS id_company_hubspot_extracted,
        business_context,
        IF(is_3p_supply, COALESCE(partner_3p_supply_extracted, 'Unknown'), NULL) AS partner_3p_supply_extracted,
        is_3p_supply,
        COALESCE(is_3p_supply AND is_3p_supply_bh, FALSE) AS is_3p_supply_bh,
        FALSE AS is_publication,
        ts_status_started
    FROM
        sale_plus_rent
    UNION ALL
    SELECT -- We add every time the status went to published or unpublished. This is going to be used for retroactive fixes.
        id_house,
        NULL AS id_company_hubspot,
        business_context,
        NULL AS partner_3p_supply,
        NULL AS is_3p_supply,
        NULL AS is_3p_supply_bh,
        TRUE AS is_publication,
        ure.ts_revision AS ts_status_started
    FROM
        datalake_ebdb_clean.listing_business_context_aud AS lbca
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON lbca.rev = ure.id
    QUALIFY
        LAG(status) OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started) IS DISTINCT FROM status
        AND status IN ('PUBLISHED', 'UNPUBLISHED')
),
-- Sometimes, mainly for leads published manually, the listing is published and then a little later it is marked as 3P Supply
-- We can retroactively fix that: if it ever became 3P supply before it was unpublished, then it should be 3P Supply since the moment it was published.
-- In other words, if the next time it was marked as 3P Supply is before the next time it was published or unpublished, it is 3P Supply
add_next AS (
    SELECT
        id_house,
        NULLIF(LAST(
            CASE WHEN is_3p_supply IS NOT NULL THEN COALESCE(id_company_hubspot_extracted, -1) END, TRUE
        ) OVER(
            PARTITION BY id_house, business_context ORDER BY ts_status_started
        ), -1) AS id_company_hubspot_current,
        NULLIF(LAST(
            CASE WHEN is_3p_supply IS NOT NULL THEN COALESCE(partner_3p_supply_extracted, -1) END, TRUE
        ) OVER(
            PARTITION BY id_house, business_context ORDER BY ts_status_started
        ), -1) AS partner_3p_supply_current,
        business_context,
        LAST(is_3p_supply, TRUE) OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started) AS is_3p_supply_current,
        LAST(is_3p_supply_bh, TRUE) OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started) AS is_3p_supply_bh_current,
        NULLIF(FIRST(
            CASE WHEN is_3p_supply THEN COALESCE(id_company_hubspot_extracted, -1) END, TRUE
        ) OVER (
            PARTITION BY id_house, business_context ORDER BY ts_status_started, NOT is_publication
            ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
        ), -1) AS id_next_company_hubspot,
        NULLIF(FIRST(
            CASE WHEN is_3p_supply THEN partner_3p_supply_extracted END, TRUE
        ) OVER (
            PARTITION BY id_house, business_context ORDER BY ts_status_started, NOT is_publication
            ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
        ), -1) AS next_partner_3p_supply,
        FIRST(
            CASE WHEN is_3p_supply THEN is_3p_supply_bh END, TRUE
        ) OVER (
            PARTITION BY id_house, business_context ORDER BY ts_status_started, NOT is_publication
            ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
        ) AS is_next_3p_supply_bh,
        FIRST(
            CASE WHEN is_3p_supply THEN ts_status_started END, TRUE
        ) OVER (
            PARTITION BY id_house, business_context ORDER BY ts_status_started, NOT is_publication
            ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
        ) AS ts_next_3p_supply,
        FIRST(
            CASE WHEN is_publication THEN ts_status_started END, TRUE
        ) OVER (
            PARTITION BY id_house, business_context ORDER BY ts_status_started, NOT is_publication
            ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
        ) AS ts_next_publication,
        ts_status_started
    FROM
        add_status_changes
),
legacy_deduplicated AS (
    SELECT
        id_house,
        CASE
            WHEN (ts_next_publication IS NULL OR ts_next_publication > ts_next_3p_supply)
            AND NOT is_3p_supply_current
                THEN id_next_company_hubspot
            ELSE id_company_hubspot_current
        END AS id_company_hubspot,
        NULL AS uuid_company,
        business_context,
        CASE
            WHEN (ts_next_publication IS NULL OR ts_next_publication > ts_next_3p_supply)
            AND NOT is_3p_supply_current
                THEN next_partner_3p_supply
            ELSE partner_3p_supply_current
        END AS partner_3p_supply,
        CASE
            WHEN (ts_next_publication IS NULL OR ts_next_publication > ts_next_3p_supply)
            AND NOT is_3p_supply_current
                THEN (ts_next_3p_supply IS NOT NULL)
            ELSE is_3p_supply_current
        END AS is_3p_supply,
        CASE
            WHEN (ts_next_publication IS NULL OR ts_next_publication > ts_next_3p_supply)
            AND NOT is_3p_supply_current
                THEN is_next_3p_supply_bh
            ELSE is_3p_supply_bh_current
        END AS is_3p_supply_bh,
        ts_status_started
    FROM
        add_next
    QUALIFY
        LAG(id_company_hubspot) OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started) IS DISTINCT FROM id_company_hubspot
        OR LAG(partner_3p_supply) OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started) IS DISTINCT FROM partner_3p_supply
        OR LAG(is_3p_supply) OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started) IS DISTINCT FROM is_3p_supply
),
legacy_with_end_date_aux (
    SELECT
        hlr.id_related,
        hlr.id_listing_business_context
    FROM
        datalake_ebdb_clean.house_listing_relation AS hlr
    JOIN
        datalake_company_clean.company AS c
        ON hlr.id_related = c.uuid_company
    JOIN
        datalake_company_clean.company_product AS cp
            ON c.id = cp.id_company
   WHERE
        hlr.related_as = 'LISTING_OWNER'
        AND hlr.source_type = 'COMPANY_REF'
        AND  cp.id_product <> 29 --PP MULTI
        GROUP BY 1, 2
),
legacy_with_end_date AS (
    SELECT
        fd.id_house,
        fd.id_company_hubspot,
        hc.uuid_company,
        fd.business_context,
        fd.partner_3p_supply,
        fd.is_3p_supply,
        fd.is_3p_supply_bh,
        fd.ts_status_started,
        LEAST(
            -- If the listing is in HubSpot or in Company, we stop the status at 2023-05-01, to use only the Company domain as source
            -- Otherwise, we keep using the legacy rules, for cases such as SHPrimeComprada
            LEAD(ts_status_started) OVER(PARTITION BY fd.id_house, fd.business_context ORDER BY fd.ts_status_started),
            IF(fd.id_company_hubspot IS NOT NULL OR hlr.id_related IS NOT NULL, ('2023-05-01'::TIMESTAMP), NULL)
        )AS ts_status_ended
    FROM
        legacy_deduplicated AS fd
    LEFT JOIN
        datalake_hubspot.company AS hc
            ON hc.id_company = fd.id_company_hubspot
    LEFT JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = fd.id_house
            AND fd.business_context = lbc.business_context
    LEFT JOIN
        legacy_with_end_date_aux AS hlr
            ON hlr.id_listing_business_context = lbc.id
    WHERE
        fd.ts_status_started < ('2023-05-01'::TIMESTAMP) -- After this date, we'll only use the company domain
        OR ( -- Except the ones which are nor in hubspot nor company, like SHPrimeComprada. These are mostly old listings
            fd.id_company_hubspot IS NULL
            AND hlr.id_related IS NULL
        )
),
company_domain_changes AS (
    SELECT
        lbc.id_house,
        hlra.id_related AS uuid_company,
        lbc.business_context,
        ure.ts_revision AS ts_status_started,
        LAG(hlra.id_related) OVER(PARTITION BY lbc.id_house, lbc.business_context ORDER BY ure.ts_revision) AS id_last
    FROM
        datalake_ebdb_clean.house_listing_relation_aud AS hlra
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON hlra.rev = ure.id
    JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id = hlra.id_listing_business_context
    WHERE
        hlra.related_as = 'LISTING_OWNER'
        AND hlra.source_type = 'COMPANY_REF'
    QUALIFY
        id_last IS DISTINCT FROM uuid_company
),
company_domain_with_end AS (
    SELECT
        cdc.id_house,
        hc.id_company AS id_company_hubspot,
        cdc.uuid_company,
        cdc.business_context,
        COALESCE(hc.extracted_3p_tag, hc.name, cc.company_name) AS partner_3p_supply,
        cdc.uuid_company IS NOT NULL AS is_3p_supply,
        cdc.uuid_company IS NOT NULL AND (hc.state IS NOT DISTINCT FROM 'MG' OR cc.state_abbreviation IS NOT DISTINCT FROM 'MG') AS is_3p_supply_bh,
        cdc.ts_status_started,
        LEAD(cdc.ts_status_started) OVER (PARTITION BY cdc.id_house, cdc.business_context ORDER BY cdc.ts_status_started) AS ts_status_ended
    FROM
        company_domain_changes AS cdc
    LEFT JOIN
        datalake_hubspot.company AS hc
            ON hc.uuid_company = cdc.uuid_company
    LEFT JOIN
        datalake_company.company AS cc
            ON cc.uuid_company = cdc.uuid_company
),
-- After may 2023, our only source is the company domain
company_domain_with_forced_start_date AS (
    SELECT
        id_house,
        id_company_hubspot,
        uuid_company,
        business_context,
        partner_3p_supply,
        is_3p_supply,
        is_3p_supply_bh,
        ts_status_started,
        ts_status_ended
    FROM
        company_domain_with_end
    WHERE
        ts_status_started >= ('2023-05-01'::TIMESTAMP)
    UNION ALL
    SELECT -- Create a fake row for each house that has a company domain before may 2023
        id_house,
        id_company_hubspot,
        uuid_company,
        business_context,
        partner_3p_supply,
        is_3p_supply,
        is_3p_supply_bh,
        ('2023-05-01'::TIMESTAMP) AS ts_status_started,
        ts_status_ended
    FROM
        company_domain_with_end
    WHERE
        ('2023-05-01'::TIMESTAMP) BETWEEN ts_status_started AND COALESCE(ts_status_ended, NOW())
)
SELECT
    id_house,
    id_company_hubspot,
    uuid_company,
    business_context,
    partner_3p_supply,
    is_3p_supply,
    is_3p_supply_bh,
    ts_status_started,
    ts_status_ended
FROM
    legacy_with_end_date
UNION ALL
SELECT
    id_house,
    id_company_hubspot,
    uuid_company,
    business_context,
    partner_3p_supply,
    is_3p_supply,
    is_3p_supply_bh,
    ts_status_started,
    ts_status_ended
FROM
    company_domain_with_forced_start_date
