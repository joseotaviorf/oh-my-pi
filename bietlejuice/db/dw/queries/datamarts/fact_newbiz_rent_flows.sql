WITH newbiz_listings AS (

    -- gets renos info
    SELECT
        dhl.sk_house_listing,
        dhl.id_house,
        DATE(dhl.ts_publication)				AS publication_date,
        DATE(dhl.ts_de_publication)				AS de_publication_date,
        dhl.status,
        dhl.is_last_version,
        dhl.house_status,
        dhl.rent,
        dhl.house_condo,
        dhl.house_iptu,
        dhl.house_predicted_price,
        dhl.house_bedrooms,
        dhl.house_total_area,
        dhl.is_exclusive,
        False 									AS is_orent,
        False									AS is_irent,
        DATE(NULL) 								AS optedin_orent_date,
        DATE(NULL) 								AS optedin_irent_date,
        dhl.last_originals_type,
        dhl.dt_last_originals_opted_in,
        dhl.dt_last_originals_opted_out,
        dhl.is_originals_active,
        MIN(DATE(fpj.sk_date_photos_uploaded)) 	AS date_job_photos_uploaded,
        MIN(DATE(ei.atualizadoem)) 				AS date_photos_uploaded,
        CASE
            WHEN date_job_photos_uploaded IS NULL
            THEN date_photos_uploaded
            WHEN date_photos_uploaded IS NULL
            THEN date_job_photos_uploaded
            WHEN date_job_photos_uploaded IS NOT NULL
             AND date_photos_uploaded IS NOT NULL
             AND date_job_photos_uploaded >= date_photos_uploaded
            THEN date_photos_uploaded
            WHEN date_job_photos_uploaded IS NOT NULL
             AND date_photos_uploaded IS NOT NULL
             AND date_photos_uploaded >= date_job_photos_uploaded
            THEN date_job_photos_uploaded
            END                                 AS init_date
    FROM dim_house_listing dhl
    LEFT JOIN fact_photo_job fpj
      ON dhl.sk_house_listing = fpj.sk_property
     AND fpj.creation_origin != 'Teste'
     AND fpj.job_status = 'Publicado'
     AND fpj.sk_date_photos_uploaded != '-1'
     AND DATE(fpj.sk_date_photos_uploaded) >= DATEADD(DAY, -7, dhl.dt_last_originals_opted_in) 
     AND DATE(fpj.sk_date_photos_uploaded) > dhl.ts_publication
    LEFT JOIN datalake_raw.ebdb_imagem ei
      ON ei.imovel_id = dhl.id_house
     AND ei.atualizadoem >= DATEADD(DAY, -7, dhl.dt_last_originals_opted_in) 
     AND ei.atualizadoem > dhl.ts_publication
    JOIN (SELECT
            -- max published listing before last originals optedin date
            dhl.id_house,
            MAX(dhl.sk_house_listing)   AS sk_house_listing
          FROM dim_house_listing dhl
          WHERE dhl.last_originals_type = 'OriginalsReno'
            AND dhl.dt_last_originals_opted_in >= dhl.ts_publication
          GROUP BY dhl.id_house
         ) max_list
      ON dhl.sk_house_listing = max_list.sk_house_listing
    WHERE dhl.last_originals_type = 'OriginalsReno'
      AND dhl.id_house NOT IN (SELECT
                      	         DISTINCT id
                               FROM datalake_raw.ebdb_imovel_aud
                               WHERE usuario_id = '994668'
                               AND usuario_mod = '1'
                               )
      AND COALESCE(fpj.sk_date_photos_uploaded::VARCHAR, ei.atualizadoem::VARCHAR) IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22

    UNION

    -- gets orent info
    SELECT
        dhl.sk_house_listing    										AS sk_house_listing,
        dhl.id_house,
        DATE(dhl.ts_publication)										AS publication_date,
        DATE(dhl.ts_de_publication)										AS de_publication_date,
        dhl.status,
        dhl.is_last_version,
        dhl.house_status,
        dhl.rent,
        dhl.house_condo,
        dhl.house_iptu,
        dhl.house_predicted_price,
        dhl.house_bedrooms,
        dhl.house_total_area,
        dhl.is_exclusive,
        True 															AS is_orent,
        False															AS is_irent,
        MIN(DATE(FROM_unixtime(CAST(rev.timestamp AS bigint) / 1000))) 	AS optedin_orent_date,
        DATE(NULL) 														AS optedin_irent_date,
        dhl.last_originals_type,
        dhl.dt_last_originals_opted_in,
        dhl.dt_last_originals_opted_out,
        dhl.is_originals_active,
        MIN(DATE(fpj.sk_date_photos_uploaded)) 							AS date_job_photos_uploaded,
        MIN(DATE(ei.atualizadoem)) 										AS date_photos_uploaded,
        CASE
            WHEN date_job_photos_uploaded IS NULL 
            THEN date_photos_uploaded
            WHEN date_photos_uploaded IS NULL 
            THEN date_job_photos_uploaded
            WHEN date_job_photos_uploaded IS NOT NULL 
             AND date_photos_uploaded IS NOT NULL 
             AND date_job_photos_uploaded >= date_photos_uploaded 
            THEN date_photos_uploaded
            WHEN date_job_photos_uploaded IS NOT NULL 
             AND date_photos_uploaded IS NOT NULL 
             AND date_photos_uploaded >= date_job_photos_uploaded
            THEN date_job_photos_uploaded
            END 														AS init_date
    FROM dim_house_listing dhl
    JOIN datalake_raw.ebdb_imovel_aud ima
      ON dhl.id_house = ima.id
     AND ima.usuario_id = '994668'
     AND ima.usuario_mod = '1'
    JOIN datalake_raw.ebdb_usuariorevisionentity rev
      ON ima.rev = rev.id
    LEFT JOIN fact_photo_job fpj
      ON dhl.sk_house_listing = fpj.sk_property
     AND fpj.creation_origin != 'Teste'
     AND fpj.job_status = 'Publicado'
     AND fpj.sk_date_photos_uploaded != '-1'
     AND DATE(fpj.sk_date_photos_uploaded) >= DATE(FROM_unixtime(CAST(rev.timestamp AS bigint) / 1000))
    LEFT JOIN datalake_raw.ebdb_imagem ei
      ON ei.imovel_id = dhl.id_house
     AND ei.atualizadoem >= DATE(FROM_unixtime(CAST(rev.timestamp AS bigint) / 1000))
    JOIN (SELECT
            -- max published listing before owner change
            dhl.id_house,
            MAX(dhl.sk_house_listing)   AS sk_house_listing
          FROM dim_house_listing dhl
          JOIN datalake_raw.ebdb_imovel_aud ima
            ON dhl.id_house = ima.id
           AND ima.usuario_id = '994668'
           AND ima.usuario_mod = '1'
          JOIN datalake_raw.ebdb_usuariorevisionentity rev
            ON ima.rev = rev.id
          WHERE dhl.ts_publication <= DATE(FROM_unixtime(CAST(rev.timestamp AS bigint) / 1000))
          GROUP BY dhl.id_house
         ) max_list
      ON dhl.sk_house_listing = max_list.sk_house_listing
    WHERE dhl.ts_publication <= DATE(FROM_unixtime(CAST(rev.timestamp AS bigint) / 1000))
      AND COALESCE(fpj.sk_date_photos_uploaded::VARCHAR, ei.atualizadoem::VARCHAR) IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20, 21, 22
    
    UNION

    -- gets ready info
    SELECT
        dhl.sk_house_listing,
        dhl.id_house,
        DATE(dhl.ts_publication)				AS publication_date,
        DATE(dhl.ts_de_publication)				AS de_publication_date,
        dhl.status,
        dhl.is_last_version,
        dhl.house_status,
        dhl.rent,
        dhl.house_condo,
        dhl.house_iptu,
        dhl.house_predicted_price,
        dhl.house_bedrooms,
        dhl.house_total_area,
        dhl.is_exclusive,
        False									AS is_orent,
        False									AS is_irent,
        DATE(NULL) 								AS optedin_orent_date,
        DATE(NULL) 								AS optedin_irent_date,
        dhl.last_originals_type,
        dhl.dt_last_originals_opted_in,
        dhl.dt_last_originals_opted_out,
        dhl.is_originals_active,
        DATE(NULL) 								AS date_job_photos_uploaded,
        DATE(NULL) 								AS date_photos_uploaded,
        DATE(dhl.ts_publication)				AS init_date	
    FROM dim_house_listing dhl
    JOIN (SELECT
            -- max published listing before last originals optedin date
            dhl.id_house,
            MAX(dhl.sk_house_listing)   AS sk_house_listing
          FROM dim_house_listing dhl
          WHERE dhl.last_originals_type = 'OriginalsReady'
            AND dhl.dt_last_originals_opted_in >= dhl.ts_publication
          GROUP BY dhl.id_house
         ) max_list
      ON dhl.sk_house_listing = max_list.sk_house_listing
    WHERE dhl.last_originals_type = 'OriginalsReady'
      AND dhl.ts_publication IS NOT NULL

    UNION
    
    -- gets irent info
    SELECT
        dhl.sk_house_listing    										AS sk_house_listing,
        dhl.id_house,
        DATE(dhl.ts_publication)										AS publication_date,
        DATE(dhl.ts_de_publication)										AS de_publication_date,
        dhl.status,
        dhl.is_last_version,
        dhl.house_status,
        dhl.rent,
        dhl.house_condo,
        dhl.house_iptu,
        dhl.house_predicted_price,
        dhl.house_bedrooms,
        dhl.house_total_area,
        dhl.is_exclusive,
        False 															AS is_orent,
        True															AS is_irent,
        DATE(NULL) 														AS optedin_orent_date,
        MIN(DATE(FROM_unixtime(CAST(rev.timestamp AS bigint) / 1000)))	AS optedin_irent_date,
        dhl.last_originals_type,
        dhl.dt_last_originals_opted_in,
        dhl.dt_last_originals_opted_out,
        dhl.is_originals_active,
        DATE(NULL) 														AS date_job_photos_uploaded,
        DATE(NULL)														AS date_photos_uploaded,
        DATE(dhl.ts_publication) 										AS init_date
    FROM dim_house_listing dhl
    JOIN datalake_raw.ebdb_imovel_aud ima
      ON dhl.id_house = ima.id
     AND ima.usuario_id = '908761'
     AND ima.usuario_mod = '1'
    JOIN datalake_raw.ebdb_usuariorevisionentity rev
      ON ima.rev = rev.id
    JOIN (SELECT
            -- max published listing before owner change
            dhl.id_house,
            MAX(dhl.sk_house_listing)   AS sk_house_listing
          FROM dim_house_listing dhl
          JOIN datalake_raw.ebdb_imovel_aud ima
            ON dhl.id_house = ima.id
           AND ima.usuario_id = '908761'
           AND ima.usuario_mod = '1'
          JOIN datalake_raw.ebdb_usuariorevisionentity rev
            ON ima.rev = rev.id
          WHERE dhl.ts_publication <= DATE(FROM_unixtime(CAST(rev.timestamp AS bigint) / 1000))
          GROUP BY dhl.id_house
         ) max_list
      ON dhl.sk_house_listing = max_list.sk_house_listing
    WHERE dhl.ts_publication <= DATE(FROM_unixtime(CAST(rev.timestamp AS bigint) / 1000))
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 25	
	)

SELECT
	nb.sk_house_listing,
	nb.id_house,
	nb.init_date,
	CASE
		WHEN nb.is_orent = true
		THEN 'oRent'
		WHEN nb.is_irent = true
		THEN 'iRent'
		ELSE nb.last_originals_type
		END													AS type,	
	COALESCE(nb.optedin_orent_date, nb.optedin_irent_date)	AS iorent_optedin_date,	
	nb.dt_last_originals_opted_in							AS originals_last_optedin_date,
	nb.dt_last_originals_opted_out,
	nb.is_originals_active,
	nb.publication_date,
	DATEDIFF(day, nb.publication_date, nb.init_date)		AS days_listing_publication_to_init_date,
	nb.de_publication_date,
	DATEDIFF(day, nb.init_date, nb.de_publication_date)		AS days_init_date_to_listing_de_publication,
	nb.status,
	nb.is_last_version,
	nb.house_status,
	nb.is_exclusive,
	hl.sk_owner,
	hl.sk_region,
	hl.sk_condo,
	nb.rent,
	nb.house_condo,
	nb.house_iptu,
	nb.house_predicted_price,
	nb.house_bedrooms,
	nb.house_total_area,
	lrf.sk_rent_flow,
	lrf.sk_booking,
	lrf.sk_booking_created_date,
	DATEDIFF(day, nb.init_date, dd1.date)					AS days_init_date_to_booking_created,
	lrf.sk_visit,
	lrf.flg_visit_completed,
	lrf.flg_visit_performed,
	lrf.sk_visit_date,
	DATEDIFF(day, nb.init_date, dd2.date)					AS days_init_date_to_visit,	
	lrf.sk_user_agent,
	lrf.sk_client,
	lrf.sk_offer,
	lrf.sk_offer_submitted_date,
	DATEDIFF(day, nb.init_date, dd3.date)					AS days_init_date_to_offer_submitted,
	lrf.sk_offer_approved_date,
	DATEDIFF(day, nb.init_date, dd4.date)					AS days_init_date_to_offer_approved,
	lrf.sk_reservation,
	lrf.sk_reservation_created_date,
	DATEDIFF(day, nb.init_date, dd5.date)					AS days_init_date_to_reservation_created,
	lrf.sk_proposal,
	lrf.sk_proposal_approved_date,
	DATEDIFF(day, nb.init_date, dd6.date)					AS days_init_date_to_proposal_approved,
	lrf.sk_proposal_processed_date,
	DATEDIFF(day, nb.init_date, dd7.date)					AS days_init_date_to_proposal_processed,
	lrf.sk_tenant_first_doc_sent_date,
	DATEDIFF(day, nb.init_date, dd8.date)					AS days_init_date_to_tenant_first_doc_sent,
	lrf.sk_tenant_manual_first_doc_sent_date,
	DATEDIFF(day, nb.init_date, dd9.date)					AS days_init_date_to_tenant_manual_first_doc_sent,
	lrf.sk_tenant_auto_first_doc_sent_date,
	DATEDIFF(day, nb.init_date, dd10.date)					AS days_init_date_to_tenant_auto_first_doc_sent,
	lrf.sk_credit_analysis_init_date,
	DATEDIFF(day, nb.init_date, dd11.date)					AS days_init_date_to_credit_analysis_init_date,
	lrf.sk_credit_analysis_end_date,
	DATEDIFF(day, nb.init_date, dd12.date)					AS days_init_date_to_credit_analysis_end_date,
	lrf.sk_credit_analysis_approved_date,
	DATEDIFF(day, nb.init_date, dd13.date)					AS days_init_date_to_credit_analysis_approved,
	lrf.sk_contract,
	lrf.sk_contract_created_date,
	DATEDIFF(day, nb.init_date, dd14.date)					AS days_init_date_to_contract_created,
	lrf.sk_contract_signed_date,
	DATEDIFF(day, nb.init_date, dd15.date)					AS days_init_date_to_contract_signed,
	lrf.sk_contract_annulment_date,
	DATEDIFF(day, nb.init_date, dd16.date)					AS days_contract_created_to_contract_annulled,
	lrf.sk_contract_canceled_date,
	DATEDIFF(day, nb.init_date, dd17.date)					AS days_contract_created_to_contract_cancelled,
	lrf.sk_rent_flow_taxonomy
FROM newbiz_listings nb
LEFT JOIN fact_house_listings hl
  ON nb.sk_house_listing = hl.sk_house_listing 
LEFT JOIN (SELECT
				fact_listing_rent_flows.*,
				dim_date.date AS booking_date
		   FROM fact_listing_rent_flows
		   LEFT JOIN dim_date
		     ON fact_listing_rent_flows.sk_booking_created_date = dim_date.sk_date
		   ) lrf
  ON nb.sk_house_listing = lrf.sk_house_listing
 AND nb.init_date <= lrf.booking_date 
LEFT JOIN dim_date dd1
  ON lrf.sk_booking_created_date = dd1.sk_date
LEFT JOIN dim_date dd2
  ON lrf.sk_visit_date = dd2.sk_date
LEFT JOIN dim_date dd3
  ON lrf.sk_offer_submitted_date = dd3.sk_date
LEFT JOIN dim_date dd4
  ON lrf.sk_offer_approved_date = dd4.sk_date
LEFT JOIN dim_date dd5
  ON lrf.sk_reservation_created_date = dd5.sk_date
LEFT JOIN dim_date dd6
  ON lrf.sk_proposal_approved_date = dd6.sk_date
LEFT JOIN dim_date dd7
  ON lrf.sk_proposal_processed_date = dd7.sk_date
LEFT JOIN dim_date dd8
  ON lrf.sk_tenant_first_doc_sent_date = dd8.sk_date
LEFT JOIN dim_date dd9
  ON lrf.sk_tenant_manual_first_doc_sent_date = dd9.sk_date
LEFT JOIN dim_date dd10
  ON lrf.sk_tenant_auto_first_doc_sent_date = dd10.sk_date
LEFT JOIN dim_date dd11
  ON lrf.sk_credit_analysis_init_date = dd11.sk_date
LEFT JOIN dim_date dd12
  ON lrf.sk_credit_analysis_end_date = dd12.sk_date
LEFT JOIN dim_date dd13
  ON lrf.sk_credit_analysis_approved_date = dd13.sk_date
LEFT JOIN dim_date dd14
  ON lrf.sk_contract_created_date = dd14.sk_date
LEFT JOIN dim_date dd15
  ON lrf.sk_contract_signed_date = dd15.sk_date
LEFT JOIN dim_date dd16
  ON lrf.sk_contract_annulment_date = dd16.sk_date
LEFT JOIN dim_date dd17
  ON lrf.sk_contract_canceled_date = dd17.sk_date
ORDER BY nb.sk_house_listing,
 		 lrf.sk_rent_flow
;