WITH houses_without_lead_conversion AS (
    WITH min_house_guarantees_aud AS (
        SELECT
            id_house,
            MIN(rev) AS rev
        FROM
            datalake_ebdb_clean.house_guarantees_aud
        WHERE guarantee_type IN ('SeguroFiancaCardiff', 'SeguroFairfax')
        GROUP BY 1
    )
    SELECT
        house.id AS id_house,
        NULL AS id_lead,
        NULL AS lead_status,
        NULL AS lead_reason,
        NULL AS reason,
        NULL AS id_conversion,
        CASE
            WHEN (house.id_user_registrant = house.id_user
                AND user.admin_type = 'Normal'
                AND user.email NOT LIKE '%quintoandar%')
            THEN NULL
            ELSE house.id_user_registrant
        END AS id_rep,
        NULL AS id_affiliate,
        house.id_user AS id_owner,
        house.id_region AS id_region,
        house.id_region AS id_first_region,
        house.dt_creation AS ts_lead,
        house.dt_creation AS ts_prospect,
        NULL AS ts_first_contact,
        NULL AS ts_conversion,
        CASE
            WHEN (house.id_user_registrant = house.id_user
                AND user.admin_type = 'Normal'
                AND user.email NOT LIKE '%quintoandar%')
            THEN ure.ts_revision
            ELSE house.dt_creation
        END AS ts_qualified,
        NULL AS ts_discarded,
        NULL AS id_user_lead_first_discarder,
        NULL AS id_user_lead_last_discarder,
        CASE
            WHEN (house.id_user_registrant = house.id_user
                AND user.admin_type = 'Normal'
                AND user.email NOT LIKE '%quintoandar%')
            THEN 'Self-Service Flow'
            ELSE 'Organic Flow'
        END AS flow,
        CASE
            WHEN (house.id_user_registrant = house.id_user
                AND user.admin_type = 'Normal'
                AND user.email NOT LIKE '%quintoandar%')
            THEN 'Self-Service'
            ELSE 'Non-Self Service'
        END AS acquisition_method,
        CASE
            WHEN (house.id_user_registrant = house.id_user
                AND user.admin_type = 'Normal'
                AND user.email NOT LIKE '%quintoandar%')
            THEN 'Organic Owner App'
            ELSE 'Admin'
        END AS acquisition_channel,
        CASE
            WHEN (house.id_user_registrant = house.id_user
                AND user.admin_type = 'Normal'
                AND user.email NOT LIKE '%quintoandar%')
            THEN 'Owner App'
            ELSE 'Admin'
        END AS acquisition_source
    FROM
        datalake_ebdb_listing.house
    LEFT JOIN
        datalake_lead.conversion_lead cl
        ON cl.id_house = house.id
    LEFT JOIN
        datalake_ebdb_user.user
        ON user.id = house.id_user_registrant
    LEFT JOIN
        min_house_guarantees_aud min_hga
        ON house.id = min_hga.id_house
    LEFT JOIN
        datalake_ebdb_user_revision_entity.user_revision_entity ure
        ON min_hga.rev = ure.id
    WHERE
        cl.id IS NULL
),
houses_without_lead AS (
    SELECT
        house.id AS id_house,
        NULL AS id_lead,
        NULL AS lead_status,
        NULL AS lead_reason,
        NULL AS reason,
        cl.id AS id_conversion,
        house.id_user_registrant AS id_rep,
        NULL AS id_affiliate,
        house.id_user AS id_owner,
        house.id_region AS id_region,
        house.id_region AS id_first_region,
        house.dt_creation AS ts_lead,
        house.dt_creation AS ts_prospect,
        ts_converted AS ts_first_contact,
        ts_converted AS ts_conversion,
        ts_converted AS ts_qualified,
        NULL AS ts_discarded,
        NULL AS id_user_lead_first_discarder,
        NULL AS id_user_lead_last_discarder,
        'Organic Flow' AS flow,
        'Non-Self Service' AS acquisition_method,
        'Inside Sales' AS acquisition_channel,
        'Admin' AS acquisition_source
    FROM
        datalake_lead.conversion_lead cl
    LEFT JOIN
        datalake_ebdb_listing.house
        ON house.id = cl.id_house
    LEFT JOIN
        datalake_ebdb_user.user
        ON user.id = house.id_user_registrant
    WHERE cl.id_converted_lead IS NULL
),
houses_with_lead AS (
    WITH lead_first_update AS (
        SELECT
            id_lead,
            MIN(rev) AS rev
        FROM
            datalake_ebdb_clean.lead_aud
        WHERE ((has_processed AND mod_has_processed)
            OR (mod_status and status != 'Novo'))
            AND NOT COALESCE(has_automatically_discarded, FALSE)
        GROUP BY 1
    ),
    lead_last_discarded AS (
        SELECT
            id_lead,
            MAX(rev) AS rev
        FROM
            datalake_ebdb_clean.lead_aud
        WHERE mod_status
            AND status = 'Descartado'
        GROUP BY 1
    ),
    lead_has_aud AS (
        SELECT
            id_lead,
            MAX(rev) AS rev
        FROM
            datalake_ebdb_clean.lead_aud
        WHERE mod_status
        GROUP BY 1
    ),
    lead_first_contact AS (
        SELECT
            lead_aud.id_lead,
            MIN(ure.ts_revision) AS ts_revision
        FROM
            datalake_ebdb_clean.lead_aud
        JOIN
            datalake_ebdb_user_revision_entity.user_revision_entity ure
            ON ure.id = lead_aud.rev
        WHERE
            lead_aud.status = 'Convertido'
            OR
            (lead_aud.status IN ('Prospeccao','Descartado')
            AND lead_aud.reason NOT IN ('OWNER_WONT_ANSWER_PHONE',
                                        'OWNER_DIDNT_ANSWER_PHONE',
                                        'ProprietarioNaoAtende',
                                        'ProprietarioNuncaAtende',
                                        'CONTACT_DIDNT_EXIST')
            AND NOT COALESCE(lead_aud.has_automatically_discarded, FALSE))
        GROUP BY 1
    ),
    lead_first_discarded AS (
        SELECT
            lead_aud.id_lead,
            MIN(ure.id) AS id_ure
        FROM datalake_ebdb_clean.lead_aud
        JOIN datalake_ebdb_user_revision_entity.user_revision_entity ure
            ON lead_aud.rev = ure.id
        WHERE lead_aud.mod_status
            AND lead_aud.status = 'Descartado'
            AND NOT lead_aud.has_automatically_discarded
        GROUP BY 1
    ),
    lead_max_discarded AS (
        SELECT
            lead_aud.id_lead,
            MAX(ure.id) AS id_ure
        FROM datalake_ebdb_clean.lead_aud
        JOIN datalake_ebdb_user_revision_entity.user_revision_entity ure
            ON lead_aud.rev = ure.id
        WHERE lead_aud.status = 'Descartado'
            AND NOT lead_aud.has_automatically_discarded
            AND (CAST(lead_aud.mod_status AS INT) + CAST(lead_aud.mod_recurring_status_count AS INT) >= 1)
        GROUP BY 1
    ),
    lead_first_region AS (
        SELECT
            lead_aud.id_lead,
            MIN(lead_aud.rev) AS rev
        FROM datalake_ebdb_clean.lead_aud
        WHERE lead_aud.id_region IS NOT NULL
        GROUP BY 1
    )
    SELECT DISTINCT
        house.id AS id_house,
        lead.id AS id_lead,
        lead.status AS lead_status,
        lead.reason AS lead_reason,
        lead.original_reason AS reason,
        cl.id AS id_conversion,
        CASE
            WHEN rep.id IS NOT NULL
                THEN rep.id
            WHEN reg.id_sales_rep IS NOT NULL
                THEN reg.id
            ELSE NULL
        END AS rep_id,
        uda.id AS id_affiliate,
        house.id_user AS id_owner,
        COALESCE(house.id_region, lead.id_region) as id_region,
        COALESCE(lead_aud_first_region.id_region, house.id_region) AS id_first_region,
        COALESCE(lead.ts_created, lead.dt_ad_created, lead.dt_picked_up) AS ts_lead,
        CASE
            WHEN has_aud.id_lead IS NOT NULL THEN ure.ts_revision
            ELSE COALESCE(lead.ts_updated, lead.ts_created) -- if there is no AUD records, we assume lead update or creation
        END AS ts_prospect,
        lfc.ts_revision AS ts_first_contact,
        cl.ts_converted AS ts_conversion,
        CASE -- when excluded by specific reasons we count the lead as a qualified lead, even if its discarded
        WHEN cl.id_converted_lead IS NOT NULL
          THEN COALESCE(cl.ts_created, cl.ts_conversion, ure.ts_revision)
        WHEN lead.reason = 'ProprietarioRecusou'
            AND lead.original_reason != 'OWNER_DIDNT_LISTEN_TO_PITCH'
          THEN COALESCE(discard_ure.ts_revision, ure.ts_revision)
        END AS ts_qualified,
        discard_ure.ts_revision as ts_discarded,
        d_ure.id_user AS id_user_lead_first_discarder,
        d_ure_max.id_user AS user_id_lead_last_discarder,
        CASE
            WHEN lead.source = 'OwnerPWA' THEN 'Self-Service Flow'
            ELSE 'Lead Flow'
        END AS flow,
        CASE
            WHEN lead.source = 'OwnerPWA' THEN 'Self-Service'
            ELSE 'Non-Self Service'
        END AS acquisition_method,
        CASE
            WHEN uda.id = 279289
                AND lead.source <> 'Reprocessado'
                THEN 'Doorman'
            WHEN affiliate_data.id_doorman_affiliate_data IS NOT NULL
                AND dad.ts_joined <= lead.ts_created
                AND affiliate_data.affiliate_type = 'Doorman'
                THEN 'Doorman'
            WHEN lead.type = 'Porteiro' THEN 'Doorman'
            WHEN lead.type = 'Afiliado' AND lead.source = 'App' THEN 'Affiliate App'
            WHEN lead.type = 'Afiliado' AND lead.source = 'Form' THEN 'Affiliate Form'
            WHEN lead.type = 'Afiliado' AND lead.source = 'Planilha' THEN 'Affiliate Spreadsheet'
            WHEN lead.type = 'Afiliado' AND lead.source = 'Desconhecida' THEN 'Affiliate Unknown'
            WHEN lead.type = 'OpenLink' AND lead.source = 'Landing' THEN 'Direct Referral'
            WHEN lead.source = 'Facebook' THEN 'Facebook'
            WHEN lead.source = 'Landing' THEN 'Landing Page Leads' -- BrokenOpenLink goes here also
            WHEN lead.source = 'Crawling' THEN 'Crawling'
            WHEN lead.source = 'OwnerPWA' AND lead.type = 'BrokenOpenLink' THEN 'Direct Referral'
            WHEN lead.source = 'OwnerPWA' AND lead.type = 'LandingMarketing' THEN 'Landing Owner App'
            WHEN lead.source = 'OwnerPWA' AND lead.type = 'LandingOpenLink' THEN 'Direct Referral'
            WHEN lead.source = 'OwnerPWA' AND lead.type = 'Organic' THEN 'Organic Owner App'
            ELSE 'Other'
        END AS acquisition_channel,
        CASE
            WHEN uda.id = 279289
                AND lead.source <> 'Reprocessado'
                THEN 'Doorman'
            WHEN affiliate_data.id_doorman_affiliate_data IS NOT NULL
                AND dad.ts_joined <= lead.ts_created
                AND affiliate_data.affiliate_type = 'Doorman'
                THEN 'Doorman'
            WHEN lead.type = 'Porteiro' THEN 'Doorman'
            WHEN lead.source = 'Reprocessado' THEN 'Reprocessed'
            WHEN lead.type = 'Afiliado' THEN 'Affiliate'
            WHEN lead.type = 'OpenLink' THEN 'Affiliate'
            WHEN lead.source = 'Facebook' THEN 'Facebook'
            WHEN lead.source = 'Landing' THEN 'Landing Page Leads' -- BrokenOpenLink goes here also
            WHEN lead.source = 'Crawling' THEN 'Crawling'
            WHEN lead.source = 'OwnerPWA' THEN 'Owner App'
            ELSE 'Other'
        END AS acquisition_source
    FROM
        datalake_lead.lead
    LEFT JOIN
        datalake_lead.conversion_lead cl
        ON cl.id_converted_lead = lead.id
    LEFT JOIN
        datalake_ebdb_listing.house
        ON house.id = cl.id_house
    LEFT JOIN
        lead_first_update lfu
        ON lfu.id_lead = lead.id
    LEFT JOIN
        datalake_ebdb_clean.lead_aud
        ON lead_aud.id_lead = lead.id
        AND lead_aud.rev = lfu.rev
    LEFT JOIN
        datalake_ebdb_user_revision_entity.user_revision_entity ure
        ON ure.id = lead_aud.rev
    LEFT JOIN
        lead_last_discarded lld
        ON lead.id = lld.id_lead
    LEFT JOIN
        datalake_ebdb_user_revision_entity.user_revision_entity discard_ure
        ON discard_ure.id = lld.rev
    LEFT JOIN
        lead_has_aud has_aud
        ON has_aud.id_lead = lead.id
    LEFT JOIN
        lead_first_contact lfc
        ON lfc.id_lead = lead.id
    LEFT JOIN
        datalake_ebdb_clean.affiliate_data
        ON affiliate_data.id = lead.id_affiliate_has_indicated
    LEFT JOIN
        datalake_ebdb_clean.doorman_affiliate_data dad
        ON affiliate_data.id_doorman_affiliate_data = dad.id
    LEFT JOIN
        datalake_ebdb_user.user uda
        ON uda.id_affiliates = affiliate_data.id
    LEFT JOIN
        datalake_ebdb_user.user rep
        ON rep.id_sales_rep = cl.id_sales_rep
    LEFT JOIN
        datalake_ebdb_user.user reg
        ON reg.id = house.id_user_registrant
    LEFT JOIN
        lead_first_discarded
        ON lead_first_discarded.id_lead = lead.id
    LEFT JOIN
        datalake_ebdb_user_revision_entity.user_revision_entity d_ure
        ON d_ure.id = lead_first_discarded.id_ure
    LEFT JOIN
        lead_max_discarded
        ON lead_max_discarded.id_lead = lead.id
    LEFT JOIN
        datalake_ebdb_user_revision_entity.user_revision_entity d_ure_max
        ON d_ure_max.id = lead_max_discarded.id_ure
    LEFT JOIN
        lead_first_region
        ON lead_first_region.id_lead = lead.id
    LEFT JOIN
        datalake_ebdb_clean.lead_aud lead_aud_first_region
        ON lead_aud_first_region.rev = lead_first_region.rev
),
listing_flows AS (
    SELECT
        *
    FROM
        houses_without_lead_conversion
    UNION ALL
    SELECT
        *
    FROM
        houses_without_lead
    UNION ALL
    SELECT
        *
    FROM
        houses_with_lead
),
base_listing_flows AS  (
    WITH photo_jobs AS (
        SELECT
            id_house,
            MIN(id) AS min_id,
            MAX(id) AS max_id
        FROM datalake_ebdb_clean.photographer_job
        GROUP BY 1
    ),
    first_rev_photo_job AS (
        SELECT
            id_photographer_job,
            MIN(rev) AS rev
        FROM datalake_ebdb_clean.photographer_job_aud
        GROUP BY 1
    ),
    photo_rep_via_house AS (
        SELECT
            house.id,
            MIN(jaud.rev) as min_rev
        FROM datalake_ebdb_listing.house
        JOIN datalake_ebdb_clean.photographer_job_aud jaud
            ON house.id = jaud.id_house
            AND jaud.mod_status
            AND jaud.status = 'Agendado'
        JOIN datalake_ebdb_user_revision_entity.user_revision_entity ure
            ON ure.id = jaud.rev
            AND (house.dt_first_publication IS NULL
                OR
                ts_revision <= house.dt_first_publication)
        JOIN datalake_ebdb_user.user
            ON user.id = ure.id_user
            AND id_sales_rep IS NOT NULL
        GROUP BY 1
    )
    SELECT
        ROW_NUMBER() OVER ( ORDER BY 0 ) AS id,
        listing_flows.lead_reason,
        listing_flows.lead_status,
        last_pj.status AS photo_job_status,
        last_pj.problem AS photo_job_reason,
        listing_flows.id_lead,
        listing_flows.id_conversion,
        last_pj.id AS id_photo_job,
        listing_flows.id_house,
        COALESCE(listing_flows.id_rep, photo_rep_ure.id_user) AS id_rep,
        listing_flows.id_rep AS id_isales_registrant,
        listing_flows.id_affiliate,
        listing_flows.id_owner,
        listing_flows.id_region,
        listing_flows.id_first_region AS id_first_region,
        photographer.id AS id_photographer,
        listing_flows.id_user_lead_first_discarder,
        listing_flows.id_user_lead_last_discarder,
        listing_flows.flow,
        listing_flows.acquisition_method,
        listing_flows.acquisition_channel,
        listing_flows.acquisition_source,
        lead.city,
        lead.neighborhood,
        (first_rev_photo_job_user.id IS NOT NULL) AS is_self_service_photo_job_scheduled,
        listing_flows.ts_lead,
        listing_flows.ts_prospect,
        listing_flows.ts_first_contact,
        listing_flows.ts_conversion,
        CASE
            WHEN (
                listing_flows.lead_status = 'Descartado'
                AND COALESCE(first_pj.ts_created,
                             first_pj.ts_scheduled,
                             first_pj.ts_photographer_accepted,
                             first_pj.ts_photos_uploaded) IS NULL
                AND ( (listing_flows.lead_reason = 'ProprietarioRecusou'
                       AND listing_flows.reason = 'OWNER_DIDNT_LISTEN_TO_PITCH')
                    OR
                    (listing_flows.lead_reason != 'ProprietarioRecusou')
                    )
                )
                THEN NULL
            ELSE listing_flows.ts_qualified
        END AS ts_qualified,
        COALESCE(first_pj.ts_created,
                 first_pj.ts_scheduled,
                 first_pj.ts_photographer_accepted,
                 first_pj.ts_photos_uploaded) AS ts_opportunity,
        house.dt_first_publication AS ts_first_listing,
        listing_flows.ts_discarded
    FROM
        listing_flows
    LEFT JOIN
        photo_jobs
        ON listing_flows.id_house = photo_jobs.id_house
    LEFT JOIN
        first_rev_photo_job
        ON photo_jobs.min_id = first_rev_photo_job.id_photographer_job
    LEFT JOIN
        datalake_ebdb_user_revision_entity.user_revision_entity first_rev_photo_job_ure
        ON first_rev_photo_job_ure.id = first_rev_photo_job.rev
    LEFT JOIN
        datalake_ebdb_user.user first_rev_photo_job_user
        ON first_rev_photo_job_user.id = first_rev_photo_job_ure.id_user
        AND first_rev_photo_job_user.id_sales_rep IS NULL
    LEFT JOIN
		datalake_ebdb_clean.photographer_job first_pj
		ON first_pj.id = photo_jobs.min_id
    LEFT JOIN
		datalake_ebdb_clean.photographer_job last_pj
		ON last_pj.id = photo_jobs.max_id
    LEFT JOIN
		datalake_ebdb_user.user photographer
		ON photographer.id_photographer_data = last_pj.id_photographer_data
	LEFT JOIN
		datalake_ebdb_listing.house
		ON house.id = listing_flows.id_house
	LEFT JOIN
		datalake_lead.lead
		ON lead.id = listing_flows.id_lead
    LEFT JOIN
        photo_rep_via_house
        ON photo_rep_via_house.id = house.id
    LEFT JOIN
        datalake_ebdb_user_revision_entity.user_revision_entity photo_rep_ure
        ON photo_rep_ure.id = photo_rep_via_house.min_rev
)
SELECT
    id,
    id_lead,
    id_conversion,
    id_photo_job,
    id_house,
    id_rep,
    id_isales_registrant,
    id_affiliate,
    id_region,
    id_first_region,
    id_user_lead_first_discarder,
    id_user_lead_last_discarder,
    flow,
    acquisition_method,
    acquisition_channel,
    acquisition_source,
    CASE
        WHEN ts_first_listing IS NOT NULL
            THEN 'Listed'
        WHEN ts_opportunity IS NOT NULL
            AND ts_first_listing IS NULL
            AND photo_job_status IN ('FotosTiradas','Completado', 'NaoListado')
            THEN 'NotListedYet'
        WHEN
            ts_opportunity IS NOT NULL
            AND ts_first_listing IS NULL
            AND photo_job_status IN ('Agendado','Iniciado','Novo')
            THEN 'PhotoJobScheduled'
        WHEN
            ts_opportunity IS NOT NULL
            AND ts_first_listing IS NULL
            AND photo_job_status = 'Cancelado'
            THEN COALESCE(photo_job_reason, 'CancelledPhotoJob')
        WHEN
            ts_opportunity IS NOT NULL
            AND ts_first_listing IS NULL
            THEN COALESCE(photo_job_reason, 'CancelledPhotoJob')
        WHEN
            ts_opportunity IS NULL
            AND ts_qualified IS NOT NULL
            AND lead_status = 'Descartado'
            THEN 'DiscardedQualified'
        WHEN
            ts_opportunity IS NULL
            AND ts_qualified IS NOT NULL
            AND lead_status = 'Convertido'
            THEN 'NoPhotoJob'
        WHEN
            ts_opportunity IS NULL
            AND ts_qualified IS NOT NULL
            AND id_conversion IS NOT NULL
            THEN 'NoPhotoJob'
        WHEN
            ts_opportunity IS NULL
            AND lead_reason = 'EmProspeccao'
            THEN 'OnHold'
        WHEN
            ts_qualified IS NULL
            AND lead_status = 'Descartado'
            THEN 'DiscardedProspect'
        WHEN
            ts_qualified IS NULL
            AND lead_status = 'Novo'
            AND city = 'Outra cidade'
            THEN 'NaoProcessadoArea'
        WHEN ts_qualified IS NULL
            AND lead_status = 'Novo'
            THEN 'NaoProcessado'
        WHEN
            flow = 'Lead Flow' AND
            ts_qualified IS NULL
            THEN 'NaoProcessado'
        WHEN
            lead_status = 'Convertido'
            AND id_conversion IS NULL
            THEN 'BrokenLeadFlow'
        WHEN
            flow = 'Lead Flow'
            AND ts_prospect IS NULL
            AND lead_status IS NULL
            THEN 'DiscardedLead'
        WHEN
            flow = 'Self-Service Flow'
            AND ts_prospect IS NOT NULL
            AND ts_qualified IS NULL
            THEN 'TermsNotAccepted'
        WHEN flow = 'Self-Service Flow'
            AND ts_qualified IS NOT NULL
            AND ts_opportunity IS NULL
            THEN 'NoPhotoJob'
        WHEN
            flow = 'Organic Flow'
            AND ts_prospect IS NOT NULL
            AND ts_qualified IS NULL
            THEN 'UnfinishedForm'
        WHEN
            flow = 'Organic Flow'
            AND ts_qualified IS NOT NULL
            AND ts_opportunity IS NULL
            THEN 'NoPhotoJob'
        ELSE 'NotMapped'
    END AS funnel_step,
    is_self_service_photo_job_scheduled,
    ROUND((BIGINT(ts_prospect) - BIGINT(ts_lead)) / 3600, 1) AS hours_lead_to_prospect,
    ROUND((BIGINT(ts_qualified) - BIGINT(ts_prospect)) / 3600, 1) AS hours_prospect_to_qualified,
    ROUND((BIGINT(ts_first_contact) - BIGINT(ts_lead)) / 3600, 1) AS hours_lead_to_first_contact,
    ROUND((BIGINT(ts_first_contact) - BIGINT(ts_prospect)) / 3600, 1) AS hours_prospect_to_first_contact,
    ROUND((BIGINT(ts_opportunity) - BIGINT(ts_qualified)) / 3600, 1) AS hours_qualified_to_opportunity,
    ROUND((BIGINT(ts_first_listing) - BIGINT(ts_opportunity)) / 3600, 1) AS hours_opportunity_to_listing,
    ROUND((BIGINT(ts_first_listing) - BIGINT(ts_lead)) / 3600, 1) AS hours_lead_to_listing,
    ROUND((BIGINT(ts_prospect) - BIGINT(ts_lead)) / 86400, 1) AS days_lead_to_prospect,
    ROUND((BIGINT(ts_qualified) - BIGINT(ts_prospect)) / 86400, 1) AS days_prospect_to_qualified,
    ROUND((BIGINT(ts_first_contact) - BIGINT(ts_lead)) / 86400, 1) AS days_lead_to_first_contact,
    ROUND((BIGINT(ts_first_contact) - BIGINT(ts_prospect)) / 86400, 1) AS days_prospect_to_first_contact,
    ROUND((BIGINT(ts_opportunity) - BIGINT(ts_qualified)) / 86400, 1) AS days_qualified_to_opportunity,
    ROUND((BIGINT(ts_first_listing) - BIGINT(ts_opportunity)) / 86400, 1) AS days_opportunity_to_listing,
    ROUND((BIGINT(ts_first_listing) - BIGINT(ts_lead)) / 86400, 1) AS days_lead_to_listing,
    CASE
        WHEN ts_conversion IS NULL AND ts_discarded IS NULL
            THEN NULL
        ELSE
            ROUND(
                (BIGINT(LEAST(
                    COALESCE(ts_conversion, DATE_ADD(ts_discarded, 1)),
                    COALESCE(ts_discarded, DATE_ADD(ts_conversion, 1))
                )) - BIGINT(ts_lead)) / 86400
            , 1)
        END AS days_lead_to_processing,
    ts_lead,
    ts_prospect,
    ts_first_contact,
    ts_conversion,
    ts_qualified,
    ts_opportunity,
    ts_first_listing,
    ts_discarded
FROM base_listing_flows