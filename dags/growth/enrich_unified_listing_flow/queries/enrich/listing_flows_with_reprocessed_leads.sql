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
    SELECT
        id_house,
        CAST(MAX(CAST(business_context = 'SALE' AS INTEGER)) AS BOOLEAN) AS is_for_sale,
        CAST(MAX(CAST(business_context = 'RENT' AS INTEGER)) AS BOOLEAN) AS is_for_rent,
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
        lf.id_isales_registrant,
        lf.id_affiliate,
        lf.id_region,
        lf.id_user_lead_first_discarder,
        lf.id_user_lead_last_discarder,
        lf.country_code,
        lf.ts_conversion,
        lf.ts_discarded,
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
        l.reason_detail AS lead_reason_detail,
        lr.reason AS lr_reason,
        l.city,
        pj.status AS photo_job_status,
        pj.problem AS photo_job_reason,
        CASE
            WHEN l.is_for_sale AND l.is_for_rent
                THEN 'Hybrid'
            WHEN l.is_for_rent
                THEN 'Only Rent'
            WHEN l.is_for_sale
                THEN 'Only Sale'
            ELSE 'Organic'
        END AS lead_context_origin,
        lf.ts_lead,
        lf.ts_prospect,
        lf.ts_qualified,
        lf.ts_opportunity,
        lf.ts_first_contact,
        lbc.is_for_rent AS lbc_is_for_rent,
        lbc.is_for_sale AS lbc_is_for_sale,
        lbc.user_registrant_rent AS lbc_user_registrant_rent,
        lbc.user_registrant_sale AS lbc_user_registrant_sale,
        lbc.ts_qualified_rent AS lbc_ts_qualified_rent,
        lbc.ts_qualified_sale AS lbc_ts_qualified_sale,
        lbc.ts_first_listing_rent AS lbc_ts_first_listing_rent,
        lbc.ts_first_listing_sale AS lbc_ts_first_listing_sale,
        lbc.ts_opt_out_rent AS lbc_ts_opt_out_rent,
        lbc.ts_opt_out_sale AS lbc_ts_opt_out_sale,
        lbc.status_rent AS lbc_status_rent,
        lbc.status_sale AS lbc_status_sale,
        h.id_user AS house_id_user,
        fpj.id_rep AS fpj_id_rep,
        l.is_for_rent AS lead_is_for_rent,
        l.is_for_sale AS lead_is_for_sale,
        CASE
            WHEN (lbc.id_house IS NULL AND h.id IS NOT NULL) -- When house is not in listing_business_context, it is for rent
                    OR lbc.is_for_rent
                    OR l.is_for_rent
                    THEN True
            ELSE False
        END AS rent_table,
        CASE
            WHEN lbc.is_for_sale
                    OR l.is_for_sale
                    THEN True
            ELSE False
        END AS sale_table
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
    LEFT JOIN datalake_ebdb_clean.photographer_job AS pj
        ON pj.id = lf.id_photo_job
    LEFT JOIN first_job
        ON first_job.id_house = h.id
    LEFT JOIN datalake_ebdb_listing_jobs.photo_job AS fpj
        ON fpj.id = first_job.id_job
),
union_contexts AS (
    SELECT
        *,
        lbc_user_registrant_rent AS lbc_user_registrant,
        lbc_ts_qualified_rent AS lbc_ts_qualified,
        lbc_ts_first_listing_rent AS lbc_ts_first_listing,
        lbc_ts_opt_out_rent AS lbc_ts_opt_out,
        lbc_status_rent AS lbc_status,
        'RENT' AS listing_flow_business_context
    FROM
        acquisition_channels
    WHERE
        rent_table = True
        
    UNION ALL
    
    SELECT
        *,
        lbc_user_registrant_sale AS lbc_user_registrant,
        lbc_ts_qualified_sale AS lbc_ts_qualified,
        lbc_ts_first_listing_sale AS lbc_ts_first_listing,
        lbc_ts_opt_out_sale AS lbc_ts_opt_out,
        lbc_status_sale AS lbc_status,
        'SALE' AS listing_flow_business_context
    FROM
        acquisition_channels
    WHERE
        sale_table = True
  
),
funnel_ts_columns AS (
    SELECT
        uc.id,
        uc.id_lead,
        uc.id_conversion,
        uc.id_photo_job,
        uc.id_house,
        uc.id_isales_registrant,
        uc.id_affiliate,
        uc.id_region,
        uc.id_user_lead_first_discarder,
        uc.id_user_lead_last_discarder,
        uc.country_code,
        uc.lbc_ts_first_listing AS ts_first_listing,
        uc.lbc_ts_opt_out AS ts_opt_out,
        uc.ts_conversion,
        uc.ts_discarded,
        uc.ts_sales_company_sent,
        uc.is_self_service_photo_job_scheduled,
        uc.flow,
        uc.acquisition_method,
        uc.acquisition_channel,
        uc.acquisition_source,
        uc.acquisition_channel_rep,
        uc.id_user_has_indicated,
        uc.is_b2b,
        uc.id_partner,
        uc.affiliate_type,
        uc.is_agent_referral,
        uc.lead_status,
        CASE
          WHEN uc.listing_flow_business_context = 'SALE'
            THEN COALESCE(uc.lead_reason_detail, uc.lead_reason)
          ELSE uc.lead_reason
        END AS lead_reason,
        uc.city,
        uc.photo_job_status,
        uc.photo_job_reason,
        uc.lead_context_origin,
        uc.listing_flow_business_context,
        uc.lbc_ts_opt_out_rent,
        uc.lbc_ts_opt_out_sale,
        uc.lbc_is_for_rent,
        uc.lbc_is_for_sale,
        CASE
            WHEN (
                uc.lbc_user_registrant = uc.house_id_user
                AND u.admin_type = 'Normal'
                AND (u.email NOT LIKE '%quintoandar%' OR u.email NOT LIKE '%actionline%')
            )
            THEN uc.fpj_id_rep
            ELSE uc.lbc_user_registrant
        END AS id_rep,
        CASE
            WHEN
              (uc.listing_flow_business_context = 'RENT' AND uc.lead_is_for_rent)
              OR (uc.listing_flow_business_context = 'SALE' AND uc.lead_is_for_sale)
                THEN uc.ts_lead
            ELSE uc.lbc_ts_qualified
        END AS ts_lead,
        CASE
            WHEN
              (uc.listing_flow_business_context = 'RENT' AND uc.lead_is_for_rent)
              OR (uc.listing_flow_business_context = 'SALE' AND uc.lead_is_for_sale)
                THEN uc.ts_prospect
            ELSE uc.lbc_ts_qualified
        END AS ts_prospect_old, -- Although the Supply 2.0 rule continues to use this field,
        -- we call it _old because deprecated rules for the prospect step are still used to maintain historical values.
        CASE
            WHEN
              (uc.listing_flow_business_context = 'RENT' AND uc.lead_is_for_rent)
              OR (uc.listing_flow_business_context = 'SALE' AND uc.lead_is_for_sale)
                THEN uc.ts_first_contact
            ELSE uc.lbc_ts_qualified
        END AS ts_first_contact,
        CASE
            WHEN (
                COALESCE(uc.lr_reason, uc.lead_reason) = 'ProprietarioRecusou'
                AND uc.lead_reason != 'OWNER_DIDNT_LISTEN_TO_PITCH'
                AND uc.id_conversion IS NULL
            )
                THEN uc.ts_qualified
            ELSE uc.lbc_ts_qualified
        END AS ts_qualified_old, -- Although the Supply 2.0 rule continues to use this field,
        -- we call it _old because deprecated rules for the qualified step are still used to maintain historical values.
        CASE
            WHEN (uc.lbc_ts_opt_out < uc.ts_opportunity AND uc.lbc_status = 'OPTED_OUT')
                THEN NULL
            WHEN (
                uc.ts_opportunity >= uc.lbc_ts_qualified
                AND (uc.lbc_ts_first_listing IS NULL OR uc.ts_opportunity <= uc.lbc_ts_first_listing)
            )
                THEN uc.ts_opportunity
            WHEN uc.lbc_ts_first_listing IS NOT NULL
                THEN uc.lbc_ts_first_listing
        END AS ts_opportunity,
        CASE
            WHEN uc.lbc_status_rent IS NULL
                THEN 'Not Qualified Yet'
            WHEN uc.lbc_status_rent = 'EDITING'
                THEN 'Editing'
            WHEN uc.lbc_status_rent = 'OPTED_OUT'
                THEN 'Opted Out'
            ELSE 'Once Published'
        END AS listing_rent_status,
        CASE
            WHEN uc.lbc_status_sale IS NULL
                THEN 'Not Qualified Yet'
            WHEN uc.lbc_status_sale = 'EDITING'
                THEN 'Editing'
            WHEN uc.lbc_status_sale = 'OPTED_OUT'
                THEN 'Opted Out'
            ELSE 'Once Published'
        END AS listing_sale_status
    FROM
        union_contexts uc
    LEFT JOIN datalake_ebdb_clean.user AS u
        ON u.id = uc.lbc_user_registrant

),
supply_2_0_prospect AS (
    SELECT
        ac.*,
        CASE
            WHEN
                (
                    IF(ac.listing_flow_business_context = 'RENT', drbc.lead_discard_rent, drbc.lead_discard_sale) IN (
                        'ForaArea',
                        'DUPLICATED_LEAD',
                        'CONTACT_ON_BLOCK_LIST'
                    )
                    OR
                    (
                        ac.listing_flow_business_context = 'RENT'
                        AND drbc.lead_discard_rent = 'HOUSE_WAS_OUT_OF_HOUSE_RENTING_REGIONS'
                    )
                    OR
                    (
                        ac.listing_flow_business_context = 'SALE'
                        AND drbc.lead_discard_sale = 'HOUSE_WAS_OUT_OF_HOUSE_SALES_REGIONS'
                   )
                )
            AND ts_opportunity IS NULL
                THEN NULL
            ELSE ac.ts_prospect_old
	    END AS ts_prospect_new,
        prospect_status,
        prospect_discard_rent,
        prospect_discard_sale
    FROM
        funnel_ts_columns ac
    LEFT JOIN datalake_listing_flow.discards_reason_by_context drbc
        ON ac.id_lead = drbc.id_lead
),
supply_2_0_qualified AS (
    SELECT
        *,
        CASE
            WHEN
                (
                    IF(listing_flow_business_context = 'RENT', prospect_discard_rent, prospect_discard_sale) IN (
                        'CONTACT_DIDNT_EXIST',
                        'HOUSE_ALREADY_PUBLISHED',
                        'CONTACT_KNOW_OWNER',
                        'CONTACT_WASNT_THE_HOUSE_OWNER',
                        'HOUSE_ALREADY_SOLD',
                        'HOUSE_WAS_A_BUSINESS_REAL_ESTATE',
                        'HOUSE_WITH_BAD_CONDITIONS',
                        'OWNER_DIDNT_ANSWER_PHONE',
                        'OWNER_DIDNT_LISTEN_TO_PITCH',
                        'OWNER_DIDNT_WANT_RECEIVE_CALL',
                        'PROPERTY_IN_OFFPLANT',
                        'HOUSE_PRICE_WAS_OUT_OF_BOUNDS',
                        'CONTACT_WAS_FROM_REAL_ESTATE_BROKER_OR_AGENT',
                        -- prospect discards
                        'ForaArea',
                        'DUPLICATED_LEAD',
                        'CONTACT_ON_BLOCK_LIST'
                    )
                    OR
                    (
                        listing_flow_business_context = 'RENT'
                        AND prospect_discard_rent IN (
                            'ONLY_PART_OF_THE_HOUSE_WAS_AVAILABLE_FOR_RENTING',
                            'HOUSE_WAS_OUT_OF_HOUSE_RENTING_REGIONS'
                        )
                    )
                    OR
                    (
                        listing_flow_business_context = 'SALE'
                        AND prospect_discard_sale = 'HOUSE_WAS_OUT_OF_HOUSE_SALES_REGIONS'
                    )
                    OR
                    (
                        listing_flow_business_context = 'RENT'
                        AND lbc_is_for_rent = False   
                    )
                    OR
                    (
                        listing_flow_business_context = 'SALE'
                        AND lbc_is_for_sale = False   
                    )
                )
                AND ts_opportunity IS NULL
                    THEN NULL
            -- This condition below was added to correct wrongly discarded qualifieds on listing_flow table
            -- TO-DO: refactor the tables involved with supply funnel step rules to avoid these additional rules
            WHEN ts_prospect_new IS NOT NULL
                AND ts_qualified_old IS NULL
                AND prospect_status IN ('CONVERTED','DISCARDED')
                    THEN COALESCE(
                        ts_conversion,
                        ts_discarded,
                        ts_prospect_new
                    )
            ELSE ts_qualified_old
        END AS ts_qualified_new
    FROM
        supply_2_0_prospect
),
supply_2_0_available_qualified AS (
    SELECT
        *,
        CASE
            WHEN
                (
                    (
                        listing_flow_business_context = 'RENT'
                        AND prospect_discard_rent IN (
                            'HOUSE_ALREADY_RENTED_AVAILABLE_IN_6_MONTHS',
                            'HOUSE_ALREADY_RENTED_AVAILABLE_IN_MORE_THAN_6_MONTHS',
                            'HOUSE_ALREADY_RENTED',
                            'OWNER_GAVE_UP_RENTING',
                            'SEASONAL_RENT',
                            'HOUSE_UNDER_MAJOR_RENOVATION',
                            'HOUSE_ALREADY_RENTED_FOR_MORE_THAN_3_MONTHS'
                        )
                    )
                    OR
                    (
                        listing_flow_business_context = 'SALE'
                        AND prospect_discard_sale IN (
                            'OWNER_GAVE_UP_SELLING',
                            'ISSUES_WITH_HOUSE_DOCUMENTATION',
                            'PROPERTY_IN_JUDICIAL_INVENTORY'
                        )
                    )
                    OR
                    (
                        listing_flow_business_context = 'RENT'
                        AND lbc_is_for_rent = False   
                    )
                    OR
                    (
                        listing_flow_business_context = 'SALE'
                        AND lbc_is_for_sale = False   
                    )
                )
                AND ts_opportunity IS NULL
                    THEN NULL
            ELSE ts_qualified_new
        END AS ts_available_qualified_new
    FROM
        supply_2_0_qualified
),
supply_2_0_turning_point AS (
    SELECT
        *,
        CASE
            WHEN DATE(COALESCE(ts_prospect_new, ts_lead)) >= DATE('2022-10-01') -- turning point date for funnel 2.0
                THEN ts_prospect_new
            ELSE ts_prospect_old
        END AS ts_prospect,
        CASE
            WHEN DATE(COALESCE(ts_qualified_new, ts_lead)) >= DATE('2022-10-01') -- turning point date for funnel 2.0
                THEN ts_qualified_new
            ELSE ts_qualified_old
        END AS ts_qualified,
        CASE
            WHEN DATE(COALESCE(ts_available_qualified_new, ts_lead)) >= DATE('2022-10-01') -- turning point date for funnel 2.0
                THEN ts_available_qualified_new
            ELSE NULL
        END AS ts_available_qualified
    FROM supply_2_0_available_qualified
),
funnel_drop_reason AS (
    SELECT
        *,
        CASE
            WHEN (ts_first_listing IS NOT NULL)
                THEN 'Listed'
            WHEN (ts_opportunity IS NOT NULL
                AND ts_first_listing IS NULL)
                AND photo_job_status IN ('FotosTiradas','Completado', 'NaoListado')
                THEN 'NotListedYet'
            WHEN (ts_opportunity IS NOT NULL
                AND ts_opt_out >= ts_opportunity
                AND ts_first_listing IS NULL)
                AND photo_job_status in ('FotosTiradas','Completado', 'NaoListado')
                THEN 'OptedOut Opportunity'
            WHEN (ts_opportunity IS NOT NULL
                AND ts_first_listing IS NULL
                AND photo_job_status in ('Agendado','Iniciado','Novo'))
                THEN 'PhotoJobScheduled'
            WHEN (ts_opportunity IS NOT NULL
                AND ts_first_listing IS NULL
                AND photo_job_status = 'Cancelado')
                THEN COALESCE(photo_job_reason, 'CancelledPhotoJob')
            WHEN (ts_opportunity IS NOT NULL
                AND ts_first_listing IS NULL)
                THEN COALESCE(photo_job_reason, 'CancelledPhotoJob')
            WHEN (ts_opportunity IS NULL
                AND ts_qualified IS NOT NULL
                AND lead_status = 'Descartado')
                THEN 'DiscardedQualified'
            WHEN (ts_opportunity IS NULL
                AND ts_qualified IS NOT NULL
                AND lead_status = 'Convertido')
                THEN 'NoPhotoJob'
            WHEN (ts_opportunity IS NULL
                AND ts_qualified IS NOT NULL
                AND id_conversion IS NOT NULL)
                THEN 'NoPhotoJob'
            WHEN (ts_opportunity IS NULL
                AND ts_qualified IS NOT NULL
                AND ts_opt_out >= ts_qualified)
                THEN 'OptedOut Qualified'
            WHEN (ts_opportunity IS NULL
                AND lead_reason = 'EmProspeccao')
                THEN 'OnHold'
            WHEN (ts_qualified IS NULL
                AND lead_status = 'Descartado')
                THEN 'DiscardedProspect'
            WHEN (ts_qualified IS NULL
                AND lead_status = 'Novo'
                AND city = 'Outra cidade')
                THEN 'NaoProcessadoArea'
            WHEN (ts_qualified IS NULL
                AND lead_status = 'Novo')
                THEN 'NaoProcessado'
            WHEN (flow = 'Lead Flow'
                AND ts_qualified IS NULL)
                THEN 'NaoProcessado'
            WHEN (lead_status = 'Convertido'
                AND id_conversion IS NULL)
                THEN 'BrokenLeadFlow'
            WHEN (flow = 'Lead Flow'
                AND ts_prospect IS NULL
                AND lead_status IS NULL)
                THEN 'DiscardedLead'
            WHEN (flow = 'Self-Service Flow'
                AND ts_prospect IS NOT NULL
                AND ts_qualified IS NULL)
                THEN 'TermsNotAccepted'
            WHEN (flow = 'Self-Service Flow'
                AND ts_qualified IS NOT NULL
                AND ts_opportunity IS NULL)
                THEN 'NoPhotoJob'
            WHEN (flow = 'Organic Flow'
                AND ts_prospect IS NOT NULL
                AND ts_qualified IS NULL)
                THEN 'UnfinishedForm'
            WHEN (flow = 'Organic Flow'
                AND ts_qualified IS NOT NULL
                AND ts_opportunity IS NULL)
                THEN 'NoPhotoJob'
            ELSE 'NotMapped'
        END AS funnel_step_old,
        CASE
            WHEN (ts_first_listing IS NOT NULL)
                    THEN 'Listed'
            WHEN (ts_opportunity IS NOT NULL
                    AND ts_first_listing IS NULL)
                    AND photo_job_status IN ('FotosTiradas','Completado', 'NaoListado')
                    THEN 'NotListedYet'
            WHEN (ts_opportunity IS NOT NULL
                    AND ts_opt_out >= ts_opportunity
                    AND ts_first_listing IS NULL)
                    AND photo_job_status in ('FotosTiradas','Completado', 'NaoListado')
                    THEN 'OptedOut Opportunity'
            WHEN (ts_opportunity IS NOT NULL
                    AND ts_first_listing IS NULL
                    AND photo_job_status in ('Agendado','Iniciado','Novo'))
                    THEN 'PhotoJobScheduled'
            WHEN (ts_opportunity IS NOT NULL
                    AND ts_first_listing IS NULL
                    AND photo_job_status = 'Cancelado')
                    THEN COALESCE(photo_job_reason, 'CancelledPhotoJob')
            WHEN (ts_opportunity IS NOT NULL
                    AND ts_first_listing IS NULL)
                    THEN COALESCE(photo_job_reason, 'CancelledPhotoJob')
            WHEN (ts_opportunity IS NULL
                    AND ts_available_qualified IS NOT NULL
                    AND lead_status = 'Descartado')
                    THEN 'DiscardedAvQualified'
            WHEN (ts_opportunity IS NULL
                    AND ts_available_qualified IS NOT NULL
                    AND lead_status = 'Convertido')
                    THEN 'NoPhotoJob'
            WHEN (ts_opportunity IS NULL
                    AND ts_available_qualified IS NOT NULL
                    AND id_conversion IS NOT NULL)
                    THEN 'NoPhotoJob'
            WHEN (ts_opportunity IS NULL
                    AND ts_available_qualified IS NOT NULL
                    AND ts_opt_out >= ts_available_qualified)
                    THEN 'OptedOut AvQualified'
            WHEN (ts_available_qualified IS NULL
                    AND ts_qualified IS NOT NULL
                    AND lead_status = 'Descartado')
                    THEN 'DiscardedQualified'
            WHEN (ts_available_qualified IS NULL
                    AND ts_qualified IS NOT NULL
                    AND ts_opt_out >= ts_qualified)
                    THEN 'OptedOut Qualified'
            WHEN (ts_opportunity IS NULL
                    AND lead_reason = 'EmProspeccao')
                    THEN 'OnHold'
            WHEN (ts_qualified IS NULL
                    AND lead_status = 'Descartado')
                    THEN 'DiscardedProspect'
            WHEN (ts_qualified IS NULL
                    AND lead_status = 'Novo'
                    AND city = 'Outra cidade')
                    THEN 'NaoProcessadoArea'
            WHEN (ts_qualified IS NULL
                    AND lead_status = 'Novo')
                    THEN 'NaoProcessado'
            WHEN (flow = 'Lead Flow'
                    AND ts_qualified IS NULL)
                    THEN 'NaoProcessado'
            WHEN (lead_status = 'Convertido'
                    AND id_conversion IS NULL)
                    THEN 'BrokenLeadFlow'
            WHEN (flow = 'Lead Flow'
                    AND ts_prospect IS NULL
                    AND lead_status IS NULL)
                    THEN 'DiscardedLead'
            WHEN (flow = 'Self-Service Flow'
                    AND ts_prospect IS NOT NULL
                    AND ts_qualified IS NULL)
                    THEN 'TermsNotAccepted'
            WHEN (flow = 'Self-Service Flow'
                    AND ts_available_qualified IS NOT NULL
                    AND ts_opportunity IS NULL)
                    THEN 'NoPhotoJob'
            WHEN (flow = 'Organic Flow'
                    AND ts_prospect IS NOT NULL
                    AND ts_qualified IS NULL)
                    THEN 'UnfinishedForm'
            WHEN (flow = 'Organic Flow'
                    AND ts_available_qualified IS NOT NULL
                    AND ts_opportunity IS NULL)
                    THEN 'NoPhotoJob'
            ELSE 'NotMapped'
        END AS funnel_step_supply2dot0
    FROM
        supply_2_0_turning_point
),
supply_2_0 AS (
    SELECT
        *,
        CASE
            WHEN DATE(COALESCE(ts_available_qualified, ts_qualified, ts_prospect, ts_lead)) >= DATE('2022-10-01') -- turning point date for funnel 2.0
                THEN funnel_step_supply2dot0
            ELSE funnel_step_old
        END AS funnel_step
    FROM
        funnel_drop_reason
),
acquisition_channels_dt_diffs AS (
    SELECT
    acquisition_channels.*,
    acquisition_channel_rep NOT LIKE 'Reprocessed%' AS is_not_reprocessed,
    -- SparkSQL's datediff ignores the time part, so we get the seconds diff and after that transform into days, hours, etc difference.
    CAST(CAST(ts_prospect AS TIMESTAMP) AS LONG) - CAST(CAST(ts_lead AS TIMESTAMP) AS LONG) AS lead_to_prospect_seconds_diff,
    CAST(CAST(ts_qualified AS TIMESTAMP) AS LONG) - CAST(CAST(ts_prospect AS TIMESTAMP) AS LONG) AS prospect_to_qualified_seconds_diff,
    CAST(CAST(ts_first_contact AS TIMESTAMP) AS LONG) - CAST(CAST(ts_lead AS TIMESTAMP) AS LONG) AS lead_to_first_contact_seconds_diff,
    CAST(CAST(ts_first_contact AS TIMESTAMP) AS LONG) - CAST(CAST(ts_prospect AS TIMESTAMP) AS LONG) AS prospect_to_first_contact_seconds_diff,
    CAST(CAST(ts_opportunity AS TIMESTAMP) AS LONG) - CAST(CAST(ts_qualified AS TIMESTAMP) AS LONG) AS qualified_to_opportunity_seconds_diff,
    CAST(CAST(ts_first_listing AS TIMESTAMP) AS LONG) - CAST(CAST(ts_opportunity AS TIMESTAMP) AS LONG) AS opportunity_to_listing_seconds_diff,
    CAST(CAST(ts_first_listing AS TIMESTAMP) AS LONG) - CAST(CAST(ts_lead AS TIMESTAMP) AS LONG) AS lead_to_listing_seconds_diff,
    CAST(CAST(LEAST(
            COALESCE(ts_conversion, ts_discarded + INTERVAL 1 DAY),
            COALESCE(ts_discarded, ts_conversion + INTERVAL 1 DAY)) AS TIMESTAMP
        ) AS LONG
    ) - CAST(CAST(ts_lead AS TIMESTAMP) AS LONG) AS lead_to_processing_seconds_diff
    FROM supply_2_0 AS acquisition_channels
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
    acq.country_code,
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
    acq.listing_rent_status,
    acq.listing_sale_status,
    acq.funnel_step,
    -- [ODS] It was necessary a ROUND + CAST to DECIMAL(x, 2) to force a round up in the decimal points and match most
    --  of DW table's values. Some values will yet diverge because this will always round UP. E.g.: 1.64 -> 1.7
    ROUND(CAST(acq.lead_to_prospect_seconds_diff / 3600 AS DECIMAL(10, 2)), 1) AS hours_lead_to_prospect,
    ROUND(CAST(acq.prospect_to_qualified_seconds_diff / 3600 AS DECIMAL(10, 2)), 1) AS hours_prospect_to_qualified,
    ROUND(CAST(acq.lead_to_first_contact_seconds_diff / 3600 AS DECIMAL(10, 2)), 1) AS hours_lead_to_first_contact,
    ROUND(CAST(acq.prospect_to_first_contact_seconds_diff / 3600 AS DECIMAL(10, 2)), 1) AS hours_prospect_to_first_contact,
    ROUND(CAST(acq.qualified_to_opportunity_seconds_diff / 3600 AS DECIMAL(10, 2)), 1) AS hours_qualified_to_opportunity,
    ROUND(CAST(acq.opportunity_to_listing_seconds_diff / 3600 AS DECIMAL(10, 2)), 1) AS hours_opportunity_to_listing,
    ROUND(CAST(acq.lead_to_listing_seconds_diff /3600 AS DECIMAL(10, 2)), 1) AS hours_lead_to_listing,
    ROUND(CAST(acq.lead_to_prospect_seconds_diff / 86400 AS DECIMAL(10, 2)), 1) AS days_lead_to_prospect,
    ROUND(CAST(acq.prospect_to_qualified_seconds_diff / 86400 AS DECIMAL(10, 2)), 1) AS days_prospect_to_qualified,
    ROUND(CAST(acq.lead_to_first_contact_seconds_diff / 86400 AS DECIMAL(10, 2)), 1) AS days_lead_to_first_contact,
    ROUND(CAST(acq.prospect_to_first_contact_seconds_diff / 86400 AS DECIMAL(10, 2)), 1) AS days_prospect_to_first_contact,
    ROUND(CAST(acq.qualified_to_opportunity_seconds_diff / 86400 AS DECIMAL(10, 2)), 1) AS days_qualified_to_opportunity,
    ROUND(CAST(acq.opportunity_to_listing_seconds_diff / 86400 AS DECIMAL(10, 2)), 1) AS days_opportunity_to_listing,
    ROUND(CAST(acq.lead_to_listing_seconds_diff / 86400 AS DECIMAL(10, 2)), 1) AS days_lead_to_listing,
    ROUND(CASE
        WHEN (acq.ts_conversion IS NULL AND acq.ts_discarded IS NULL)
            THEN NULL
        ELSE CAST(acq.lead_to_processing_seconds_diff / 86400 AS DECIMAL(10, 2))
    END, 1) AS days_lead_to_processing,
    -- acq.ts_opt_out,
    acq.lbc_ts_opt_out_rent AS ts_opt_out_rent,
    acq.lbc_ts_opt_out_sale AS ts_opt_out_sale,
    acq.ts_lead,
    acq.ts_prospect,
    acq.ts_first_contact,
    acq.ts_conversion,
    acq.ts_qualified,
    acq.ts_available_qualified,
    acq.ts_opportunity,
    acq.ts_first_listing,
    acq.ts_discarded,
    acq.ts_sales_company_sent,
    acq.listing_flow_business_context
FROM
    acquisition_channels_dt_diffs AS acq
LEFT JOIN legacy_doorman AS ld
    ON acq.id_house = ld.id_house
-- Filter to remove Casa Mineira listings included in Quinto Andar tables due to the BBB 22 campaign
LEFT JOIN
  datalake_ebdb_listing.house AS h
    ON h.id = acq.id_house
      AND h.internal_admin_info = '3P\n[FS-CM]'
WHERE
  h.id IS NULL