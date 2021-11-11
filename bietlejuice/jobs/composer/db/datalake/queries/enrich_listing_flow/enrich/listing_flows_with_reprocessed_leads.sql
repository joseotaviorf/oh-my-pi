WITH reproc_leads AS (
    SELECT
        rl.id,
        l.source,
        l.type,
        l.id_user_has_indicated,
        l.id_agent,
        l.affiliate_type
    FROM
        datalake_lead.reprocessed_lead AS rl
    JOIN datalake_lead.lead AS l
        ON l.id = rl.id_origin_lead
),
lbc AS (
    WITH _lbc AS (
        SELECT
            id_house,
            MAX(CAST(business_context = 'SALE' AS INTEGER)) AS is_for_sale,
            MAX(CAST(business_context = 'RENT' AS INTEGER)) AS is_for_rent,
            MAX(
                CASE
                    WHEN lbc.business_context = 'SALE' THEN lbc.status
                END
            ) AS status_sale,
            MAX(
                CASE
                    WHEN lbc.business_context = 'RENT' THEN lbc.status
                END
            ) AS status_rent,
            MAX(
                CASE
                    WHEN lbc.business_context = 'SALE' THEN lbc.ts_created
                END
            ) AS ts_qualified_sale,
            MAX(
                CASE
                    WHEN lbc.business_context = 'RENT' THEN lbc.ts_created
                END
            ) AS ts_qualified_rent,
            MAX(
                CASE
                    WHEN lbc.business_context = 'SALE' THEN lbc.ts_first_listing
                END
            ) AS ts_first_listing_sale,
            MAX(
                CASE
                    WHEN lbc.business_context = 'RENT' THEN lbc.ts_first_listing
                END
            ) AS ts_first_listing_rent,
            MAX(
                CASE
                    WHEN lbc.business_context = 'SALE' THEN lbc.ts_opt_out_sale
                END
            ) AS ts_opt_out_sale,
            MAX(
                CASE
                    WHEN lbc.business_context = 'RENT' THEN lbc.ts_opt_out_rent
                END
            ) AS ts_opt_out_rent,
            MAX(
                CASE
                    WHEN lbc.business_context = 'SALE' THEN lbc.user_listing_registrant_sale
                END
            ) AS user_registrant_sale,
            MAX(
                CASE
                    WHEN lbc.business_context = 'RENT' THEN lbc.user_listing_registrant_rent
                END
            ) AS user_registrant_rent
        FROM
           datalake_ebdb_listing.listing_business_context AS lbc
        GROUP BY 1
    )
    SELECT
        id_house,
        CAST(is_for_sale AS BOOLEAN) AS is_for_sale,
        CAST(is_for_rent AS BOOLEAN) AS is_for_rent,
        status_sale,
        status_rent,
        CAST(ts_qualified_sale AS DATE) AS dt_qualified_sale,
        CAST(ts_qualified_rent AS DATE) AS dt_qualified_rent,
        CAST(ts_first_listing_sale AS DATE) AS dt_first_listing_sale,
        CAST(ts_first_listing_rent AS DATE) AS dt_first_listing_rent,
        CAST(ts_opt_out_sale AS DATE) AS dt_opt_out_sale,
        CAST(ts_opt_out_rent AS DATE) AS dt_opt_out_rent,
        user_registrant_sale,
        user_registrant_rent
    FROM _lbc
),
first_job AS (
    SELECT
        id_house,
        MIN(id) AS id_job
    FROM datalake_ebdb_listing_jobs.photo_job
    WHERE creation_origin <> 'Prop'
    GROUP by id_house
),
b2b_prime_draft AS (
    SELECT
        l.id AS id_lead,
        MAX(pa_b2b.id_partner) AS id_partner
    FROM
        datalake_lead.lead AS l
    JOIN datalake_ebdb_clean.user AS u_b2b
        ON u_b2b.main_phone = l.advertiser_phone
    JOIN datalake_ebdb_clean.partner_agent AS pa_b2b
        ON pa_b2b.id_user = u_b2b.id
   	LEFT JOIN datalake_ebdb_clean.partner p_b2b
    	ON p_b2b.id = pa_b2b.id_partner
	WHERE l.source = 'OwnerPWA' and p_b2b.type = 'PRIME'
    GROUP BY 1
),
partner_agent_b2b AS (
	SELECT
	    pa.*
	FROM datalake_ebdb_clean.partner_agent pa
    LEFT JOIN datalake_ebdb_clean.partner p_b2b
        ON p_b2b.id = pa.id_partner
    WHERE p_b2b.type = 'PRIME'
),
acquisition_channels AS (
    SELECT
        lf.id,
        lf.id_lead,
        lf.id_conversion,
        lf.id_photo_job,
        lf.id_house,
        CASE
            WHEN (
                lbc.user_registrant_rent = h.id_user
                AND u.admin_type = 'Normal'
                AND (u.email NOT LIKE '%quintoandar%' OR u.email NOT LIKE '%actionline%')
            )
            THEN fpj.id_rep
            ELSE lbc.user_registrant_rent
        END AS id_rep,
        lf.id_isales_registrant,
        lf.id_affiliate,
        lf.id_region,
        lf.id_user_lead_first_discarder,
        lf.id_user_lead_last_discarder,
        CASE
            WHEN l.is_for_rent
             THEN lf.dt_lead
            ELSE lbc.dt_qualified_rent
        END AS dt_lead,
        CASE
            WHEN l.is_for_rent
             THEN lf.dt_prospect
            ELSE lbc.dt_qualified_rent
        END AS dt_prospect,
        CASE
            WHEN l.is_for_rent
             THEN lf.dt_first_contact
            ELSE lbc.dt_qualified_rent
        END AS dt_first_contact,
        lf.dt_conversion,
        CASE
            WHEN (
                COALESCE(lr.reason, l.reason) = 'ProprietarioRecusou'
                AND l.reason != 'OWNER_DIDNT_LISTEN_TO_PITCH'
                AND lf.id_conversion IS NULL
            )
                THEN lf.dt_qualified
            ELSE lbc.dt_qualified_rent
        END AS dt_qualified,
        CASE
            WHEN (lbc.dt_opt_out_rent < lf.dt_opportunity AND lbc.status_rent = 'OPTED_OUT')
                THEN NULL
            WHEN (
                lf.dt_opportunity >= lbc.dt_qualified_rent
                AND (lbc.dt_first_listing_rent IS NULL OR lf.dt_opportunity <= lbc.dt_first_listing_rent)
            )
                THEN lf.dt_opportunity
            WHEN lbc.dt_first_listing_rent IS NOT NULL
                THEN lbc.dt_first_listing_rent
        END AS dt_opportunity,
        lbc.dt_first_listing_rent AS dt_first_listing,
        lf.dt_discarded,
        lsc.ts_sales_company_sent,
        lf.is_self_service_photo_job_scheduled,
        lf.flow,
        lf.acquisition_method,
        lf.acquisition_channel,
        lf.acquisition_source,
        CASE
            WHEN l.source = 'Reprocessado' AND rl.source = 'Landing'
                THEN 'Reprocessed Landing'
            WHEN l.source = 'Reprocessado' AND rl.type = 'Afiliado'
                THEN 'Reprocessed Affiliate'
            WHEN l.source = 'Reprocessado'
                THEN 'Reprocessed Others'
            ELSE lf.acquisition_channel
        END AS acquisition_channel_rep,
        rl.id_user_has_indicated,
        COALESCE(
            COALESCE(rl.affiliate_type, l.affiliate_type) = 'B2BPartner'
            OR COALESCE(pa_b2b.id, b2b_prime_draft.id_lead) IS NOT NULL,
            FALSE
        ) AS is_b2b,
        b2b_prime_draft.id_partner,
        COALESCE(rl.affiliate_type, l.affiliate_type) AS affiliate_type,
        COALESCE(rl.id_agent, l.id_agent) IS NOT NULL AS is_agent_referral,
        l.status AS lead_status,
        l.reason AS lead_reason,
        l.city,
        pj.status AS photo_job_status,
        pj.problem AS photo_job_reason,
        lbc.dt_opt_out_rent,
        CASE
            WHEN l.is_for_sale AND l.is_for_rent
                THEN 'Hybrid'
            WHEN l.is_for_rent
                THEN 'Only Rent'
            WHEN l.is_for_sale
                THEN 'Only Sale'
            ELSE 'Organic'
        END AS lead_context_origin,
        CASE
            WHEN lbc.status_sale IS NULL
                THEN 'Not Qualified Yet'
            WHEN lbc.status_sale = 'EDITING'
                THEN 'Editing'
            WHEN lbc.status_sale = 'OPTED_OUT'
                THEN 'Opted Out'
            ELSE 'Once Published'
        END AS listing_sale_status
    FROM datalake_listing_flow.listing_flow AS lf
    LEFT JOIN datalake_lead.lead AS l
        ON l.id = lf.id_lead
    LEFT JOIN datalake_ebdb_clean.lead_reason AS lr
        ON l.reason = lr.reason_detail
    LEFT JOIN reproc_leads AS rl
        ON rl.id = lf.id_lead
    LEFT JOIN datalake_ebdb_listing.house AS h
        ON h.id = lf.id_house
    LEFT JOIN partner_agent_b2b pa_b2b
        ON pa_b2b.id_user = h.id_user
    LEFT JOIN b2b_prime_draft
        ON b2b_prime_draft.id_lead = l.id
    LEFT JOIN lbc
        ON lbc.id_house = h.id
    LEFT JOIN datalake_wololo_lead.lead_sales_company AS lsc
        ON lsc.id_lead = l.id
    LEFT JOIN datalake_ebdb_clean.user AS u
        ON u.id = lbc.user_registrant_rent
    LEFT JOIN datalake_ebdb_clean.photographer_job AS pj
        ON pj.id = lf.id_photo_job
    LEFT JOIN first_job
        ON first_job.id_house = h.id
    LEFT JOIN datalake_ebdb_listing_jobs.photo_job AS fpj
        ON fpj.id = first_job.id_job
    WHERE
        (lbc.id_house IS NULL AND h.id IS NOT NULL) -- When house is not in listing_business_context, it is for rent
        OR lbc.is_for_rent
        OR l.is_for_rent
),
acquisition_channels_dt_diffs AS (
    SELECT
    acquisition_channels.*,
    acquisition_channel_rep NOT LIKE 'Reprocessed%' AS is_not_reprocessed,
    -- SparkSQL's datediff ignores the time part, so we get the seconds diff and after that transform into days, hours, etc difference.
    CAST(CAST(dt_prospect AS TIMESTAMP) AS LONG) - CAST(CAST(dt_lead AS TIMESTAMP) AS LONG) AS lead_to_prospect_seconds_diff,
    CAST(CAST(dt_qualified AS TIMESTAMP) AS LONG) - CAST(CAST(dt_prospect AS TIMESTAMP) AS LONG) AS prospect_to_qualified_seconds_diff,
    CAST(CAST(dt_first_contact AS TIMESTAMP) AS LONG) - CAST(CAST(dt_lead AS TIMESTAMP) AS LONG) AS lead_to_first_contact_seconds_diff,
    CAST(CAST(dt_first_contact AS TIMESTAMP) AS LONG) - CAST(CAST(dt_prospect AS TIMESTAMP) AS LONG) AS prospect_to_first_contact_seconds_diff,
    CAST(CAST(dt_opportunity AS TIMESTAMP) AS LONG) - CAST(CAST(dt_qualified AS TIMESTAMP) AS LONG) AS qualified_to_opportunity_seconds_diff,
    CAST(CAST(dt_first_listing AS TIMESTAMP) AS LONG) - CAST(CAST(dt_opportunity AS TIMESTAMP) AS LONG) AS opportunity_to_listing_seconds_diff,
    CAST(CAST(dt_first_listing AS TIMESTAMP) AS LONG) - CAST(CAST(dt_lead AS TIMESTAMP) AS LONG) AS lead_to_listing_seconds_diff,
    CAST(
        CAST(dt_lead AS TIMESTAMP) AS LONG) - CAST(
            CAST(LEAST(
                COALESCE(dt_conversion, dt_discarded + INTERVAL 1 DAY),
                COALESCE(dt_discarded, dt_conversion + INTERVAL 1 DAY)) AS TIMESTAMP
            ) AS LONG
    ) AS lead_to_processing_seconds_diff
    FROM acquisition_channels
),
legacy_doorman AS (
    SELECT
        status,
        892700000 + id_short_house AS id_house
    FROM datalake_gsheets_clean.legacy_doorman
    WHERE status IN ('Listing', 'Alugado', 'Foto', 'Foto com problema', 'Lead')
        AND id_short_house IS NOT NULL
)
SELECT
    acq.id,
    acq.id_lead,
    acq.id_conversion,
    acq.id_photo_job,
    acq.id_house,
    acq.id_rep,
    acq.id_isales_registrant,
    acq.id_affiliate,
    acq.id_region,
    acq.id_partner,
    acq.id_user_has_indicated,
    acq.id_user_lead_first_discarder,
    acq.id_user_lead_last_discarder,
    acq.is_self_service_photo_job_scheduled,
    acq.is_not_reprocessed,
    acq.is_b2b,
    acq.is_agent_referral,
    CASE
        WHEN ld.id_house IS NOT NULL
            AND acq.is_not_reprocessed
            THEN TRUE
        ELSE acq.acquisition_source = 'Doorman'
    END AS is_doorman,
    CASE
        WHEN ld.id_house IS NOT NULL
            AND acq.is_not_reprocessed
            THEN 'Lead Flow'
        ELSE acq.flow
    END AS flow,
    CASE
        WHEN ld.id_house IS NOT NULL
            AND acq.is_not_reprocessed
            THEN 'Non-Self Service'
        ELSE acq.acquisition_method
    END AS acquisition_method,
    CASE
        WHEN ld.id_house IS NOT NULL
            AND acq.is_not_reprocessed
            THEN 'Doorman'
        ELSE acq.acquisition_channel_rep
    END AS acquisition_channel,
    CASE
        WHEN ld.id_house IS NOT NULL
            AND acq.is_not_reprocessed
            THEN 'Doorman'
        ELSE acq.acquisition_source
    END AS acquisition_source,
    acq.acquisition_channel_rep,
    acq.affiliate_type,
    acq.lead_context_origin,
    acq.listing_sale_status,
    CASE
        WHEN (acq.dt_first_listing IS NOT NULL)
            THEN 'Listed'
        WHEN (acq.dt_opportunity IS NOT NULL
            AND acq.dt_first_listing IS NULL)
            AND acq.photo_job_status IN ('FotosTiradas','Completado', 'NaoListado')
            THEN 'NotListedYet'
        WHEN (acq.dt_opportunity IS NOT NULL
            AND acq.dt_opt_out_rent >= acq.dt_opportunity
            AND acq.dt_first_listing IS NULL)
            AND acq.photo_job_status in ('FotosTiradas','Completado', 'NaoListado')
            THEN 'OptedOut Opportunity'
        WHEN (acq.dt_opportunity IS NOT NULL
            AND acq.dt_first_listing IS NULL
            AND acq.photo_job_status in ('Agendado','Iniciado','Novo'))
            THEN 'PhotoJobScheduled'
        WHEN (acq.dt_opportunity IS NOT NULL
            AND acq.dt_first_listing IS NULL
            AND acq.photo_job_status = 'Cancelado')
            THEN COALESCE(acq.photo_job_reason, 'CancelledPhotoJob')
        WHEN (acq.dt_opportunity IS NOT NULL
            AND acq.dt_first_listing IS NULL)
            THEN COALESCE(acq.photo_job_reason, 'CancelledPhotoJob')
        WHEN (acq.dt_opportunity IS NULL
            AND acq.dt_qualified IS NOT NULL
            AND acq.lead_status = 'Descartado')
            THEN 'DiscardedQualified'
        WHEN (acq.dt_opportunity IS NULL
            AND acq.dt_qualified IS NOT NULL
            AND acq.lead_status = 'Convertido')
            THEN 'NoPhotoJob'
        WHEN (acq.dt_opportunity IS NULL
            AND acq.dt_qualified IS NOT NULL
            AND acq.id_conversion IS NOT NULL)
            THEN 'NoPhotoJob'
        WHEN (acq.dt_opportunity IS NULL
            AND acq.dt_qualified IS NOT NULL
            AND acq.dt_opt_out_rent >= acq.dt_qualified)
            THEN 'OptedOut Qualified'
        WHEN (acq.dt_opportunity IS NULL
            AND acq.lead_reason = 'EmProspeccao')
            THEN 'OnHold'
        WHEN (acq.dt_qualified IS NULL
            AND acq.lead_status = 'Descartado')
            THEN 'DiscardedProspect'
        WHEN (acq.dt_qualified IS NULL
            AND acq.lead_status = 'Novo'
            AND acq.city = 'Outra cidade')
            THEN 'NaoProcessadoArea'
        WHEN (acq.dt_qualified IS NULL
            AND acq.lead_status = 'Novo')
            THEN 'NaoProcessado'
        WHEN (acq.flow = 'Lead Flow'
            AND acq.dt_qualified IS NULL)
            THEN 'NaoProcessado'
        WHEN (acq.lead_status = 'Convertido'
            AND acq.id_conversion IS NULL)
            THEN 'BrokenLeadFlow'
        WHEN (acq.flow = 'Lead Flow'
            AND acq.dt_prospect IS NULL
            AND acq.lead_status IS NULL)
            THEN 'DiscardedLead'
        WHEN (acq.flow = 'Self-Service Flow'
            AND acq.dt_prospect IS NOT NULL
            AND acq.dt_qualified IS NULL)
            THEN 'TermsNotAccepted'
        WHEN (acq.flow = 'Self-Service Flow'
            AND acq.dt_qualified IS NOT NULL
            AND acq.dt_opportunity IS NULL)
            THEN 'NoPhotoJob'
        WHEN (acq.flow = 'Organic Flow'
            AND acq.dt_prospect IS NOT NULL
            AND acq.dt_qualified IS NULL)
            THEN 'UnfinishedForm'
        WHEN (acq.flow = 'Organic Flow'
            AND acq.dt_qualified IS NOT NULL
            AND acq.dt_opportunity IS NULL)
            THEN 'NoPhotoJob'
        ELSE 'NotMapped'
    END AS funnel_step,
    CAST(acq.lead_to_prospect_seconds_diff / 3600 AS INTEGER) AS hours_lead_to_prospect,
    CAST(acq.prospect_to_qualified_seconds_diff / 3600 AS INTEGER) AS hours_prospect_to_qualified,
    CAST(acq.lead_to_first_contact_seconds_diff / 3600 AS INTEGER) AS hours_lead_to_first_contact,
    CAST(acq.prospect_to_first_contact_seconds_diff / 3600 AS INTEGER) AS hours_prospect_to_first_contact,
    CAST(acq.qualified_to_opportunity_seconds_diff / 3600 AS INTEGER) AS hours_qualified_to_opportunity,
    CAST(acq.opportunity_to_listing_seconds_diff / 3600 AS INTEGER) AS hours_opportunity_to_listing,
    CAST(acq.lead_to_listing_seconds_diff /3600 AS INTEGER) AS hours_lead_to_listing,
    CAST(acq.lead_to_prospect_seconds_diff / 86400 AS INTEGER) AS days_lead_to_prospect,
    CAST(acq.prospect_to_qualified_seconds_diff / 86400 AS INTEGER) AS days_prospect_to_qualified,
    CAST(acq.lead_to_first_contact_seconds_diff / 86400 AS INTEGER) AS days_lead_to_first_contact,
    CAST(acq.prospect_to_first_contact_seconds_diff / 86400 AS INTEGER) AS days_prospect_to_first_contact,
    CAST(acq.qualified_to_opportunity_seconds_diff / 86400 AS INTEGER) AS days_qualified_to_opportunity,
    CAST(acq.opportunity_to_listing_seconds_diff / 86400 AS INTEGER) AS days_opportunity_to_listing,
    CAST(acq.lead_to_listing_seconds_diff / 86400 AS INTEGER) AS days_lead_to_listing,
    CASE
      WHEN (acq.dt_conversion IS NULL AND acq.dt_discarded IS NULL)
        THEN NULL
      ELSE CAST(acq.lead_to_processing_seconds_diff / 86400 AS INTEGER)
    END AS days_lead_to_processing,
    acq.dt_opt_out_rent,
    acq.dt_lead,
    acq.dt_prospect,
    acq.dt_first_contact,
    acq.dt_conversion,
    acq.dt_qualified,
    acq.dt_opportunity,
    acq.dt_first_listing,
    acq.dt_discarded,
    acq.ts_sales_company_sent
FROM
    acquisition_channels_dt_diffs AS acq
LEFT JOIN legacy_doorman AS ld
    ON acq.id_house = ld.id_house