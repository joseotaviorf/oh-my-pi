WITH newbiz_listings_version AS (

  -- get newbiz listings last flagged version
  SELECT *
  FROM (
    SELECT
      dhl.id_house,
      dhl.sk_house_listing								      AS sk_house_listing,
      DATE(dhl.ts_publication)							    AS publication_date,
      newbiz_flg.specialconditiontype,
      newbiz_flg.optedinat,
      newbiz_flg.optedoutat,
      RANK() OVER (PARTITION BY dhl.id_house,
                    newbiz_flg.specialconditiontype
            ORDER BY dhl.sk_house_listing DESC)	AS _rank
    FROM dim_house_listing dhl
    JOIN (
      SELECT
        hsc.house_id,
        sc.specialconditiontype,
        DATE(sc.optedinat)			AS optedinat,
        DATE(sc.optedoutat)			AS optedoutat
      FROM datalake_raw.ebdb_housespecialcondition hsc
      JOIN datalake_raw.ebdb_specialcondition sc
        ON hsc.specialcondition_id = sc.id
      WHERE sc.specialconditiontype IN ('ORent', 'IRent', 'OriginalsReno', 'OriginalsReady')
        AND sc.optedoutat IS NULL
        ) newbiz_flg
      ON dhl.id_house = newbiz_flg.house_id
    WHERE (dhl.sk_house_listing LIKE '%000' AND (dhl.is_last_version = true OR dhl.is_last_version IS NULL))
          OR
          (DATE(dhl.ts_publication) <= newbiz_flg.optedinat)
    ) base
  WHERE _rank = 1 -- make sure we get only the listing first version or 
                  -- the current version as when it was flagged as newbiz
  ),

newbiz_listings AS (

    -- get renos info
    SELECT
        dhl.sk_house_listing,
        dhl.id_house,
        DATE(dhl.ts_publication)                AS publication_date,
        --DATE(dhl.ts_last_de_publication)             AS de_publication_date,
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
        nlv.specialconditiontype                AS newbiz_type,
        nlv.optedinat,
        nlv.optedoutat,
        MIN(DATE(fpj.sk_date_photos_uploaded)) 	AS date_job_photos_uploaded,
        MIN(DATE(ei.atualizadoem))              AS date_photos_uploaded,
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
    JOIN newbiz_listings_version nlv
      ON dhl.id_house = nlv.id_house
     AND dhl.sk_house_listing >= nlv.sk_house_listing -- make sure we do not get listing older versions
    LEFT JOIN fact_photo_job fpj
      ON dhl.sk_house_listing = fpj.sk_house_listing
     AND fpj.creation_origin != 'Teste'
     AND fpj.job_status = 'Publicado'
     AND fpj.sk_date_photos_uploaded != '-1'
     AND DATE(fpj.sk_date_photos_uploaded) >= DATEADD(DAY, -7, nlv.optedinat) -- OriginalsReno optedin can be done 7days before photo upload 
     AND DATE(fpj.sk_date_photos_uploaded) > dhl.ts_publication
    LEFT JOIN datalake_raw.ebdb_imagem ei
      ON ei.imovel_id = dhl.id_house
     AND ei.atualizadoem >= DATEADD(DAY, -7, nlv.optedinat) -- OriginalsReno optedin can be done 7days before photo upload
     AND ei.atualizadoem > dhl.ts_publication
    WHERE nlv.specialconditiontype = 'OriginalsReno'
      AND COALESCE(fpj.sk_date_photos_uploaded::VARCHAR, ei.atualizadoem::VARCHAR) IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16--, 17

    UNION

    -- gets orent info
    SELECT
        dhl.sk_house_listing    										AS sk_house_listing,
        dhl.id_house,
        DATE(dhl.ts_publication)										AS publication_date,
        --DATE(dhl.ts_last_de_publication)									AS de_publication_date,
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
        nlv.specialconditiontype                    AS newbiz_type,
        nlv.optedinat,
        nlv.optedoutat,
        MIN(DATE(fpj.sk_date_photos_uploaded))      AS date_job_photos_uploaded,
        MIN(DATE(ei.atualizadoem))                  AS date_photos_uploaded,
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
            END                                     AS init_date
    FROM dim_house_listing dhl
    JOIN newbiz_listings_version nlv
      ON dhl.id_house = nlv.id_house
     AND dhl.sk_house_listing >= nlv.sk_house_listing -- make sure we do not get listing older versions
    LEFT JOIN fact_photo_job fpj
      ON dhl.sk_house_listing = fpj.sk_house_listing
     AND fpj.creation_origin != 'Teste'
     AND fpj.job_status = 'Publicado'
     AND fpj.sk_date_photos_uploaded != '-1'
     AND DATE(fpj.sk_date_photos_uploaded) >= DATEADD(DAY, -7, nlv.optedinat) -- ORent optedin can be done 7days before photo upload 
     AND DATE(fpj.sk_date_photos_uploaded) > dhl.ts_publication
    LEFT JOIN datalake_raw.ebdb_imagem ei
      ON ei.imovel_id = dhl.id_house
     AND ei.atualizadoem >= DATEADD(DAY, -7, nlv.optedinat) -- ORent optedin can be done 7days before photo upload
     AND ei.atualizadoem > dhl.ts_publication
    WHERE nlv.specialconditiontype = 'ORent'
      AND COALESCE(fpj.sk_date_photos_uploaded::VARCHAR, ei.atualizadoem::VARCHAR) IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16--, 17

    UNION

    -- gets ready info
    SELECT
        dhl.sk_house_listing,
        dhl.id_house,
        DATE(dhl.ts_publication)			AS publication_date,
        --DATE(dhl.ts_last_de_publication)   AS de_publication_date,
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
        nlv.specialconditiontype      AS newbiz_type,
        nlv.optedinat,
        nlv.optedoutat,
        DATE(NULL)                    AS date_job_photos_uploaded,
        DATE(NULL)                    AS date_photos_uploaded,
        DATE(dhl.ts_publication)      AS init_date	
    FROM dim_house_listing dhl
    JOIN newbiz_listings_version nlv
      ON dhl.id_house = nlv.id_house
     AND dhl.sk_house_listing >= nlv.sk_house_listing -- make sure we do not get listing older versions
    WHERE nlv.specialconditiontype = 'OriginalsReady'

    UNION
    
    -- gets irent info
    SELECT
        dhl.sk_house_listing    			AS sk_house_listing,
        dhl.id_house,
        DATE(dhl.ts_publication)			AS publication_date,
        --DATE(dhl.ts_last_de_publication)   AS de_publication_date,
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
        nlv.specialconditiontype      AS newbiz_type,
        nlv.optedinat,
        nlv.optedoutat,
        DATE(NULL)                    AS date_job_photos_uploaded,
        DATE(NULL)                    AS date_photos_uploaded,
        DATE(dhl.ts_publication)      AS init_date	
    FROM dim_house_listing dhl
    JOIN newbiz_listings_version nlv
      ON dhl.id_house = nlv.id_house
     AND dhl.sk_house_listing >= nlv.sk_house_listing -- make sure we do not get listing older versions
    WHERE nlv.specialconditiontype = 'IRent'
	  )

SELECT
	nb.sk_house_listing,
	nb.id_house,
	nb.init_date,
	nb.newbiz_type,
	nb.optedinat,
  nb.optedoutat,
	nb.publication_date,
	DATEDIFF(day, nb.publication_date, nb.init_date)      AS days_listing_publication_to_init_date,
--	nb.de_publication_date,
--	DATEDIFF(day, nb.init_date, nb.de_publication_date)   AS days_init_date_to_listing_de_publication,
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
	DATEDIFF(day, nb.init_date, dd10.date)				AS days_init_date_to_tenant_auto_first_doc_sent,
	lrf.sk_credit_analysis_init_date,
	DATEDIFF(day, nb.init_date, dd11.date)				AS days_init_date_to_credit_analysis_init_date,
	lrf.sk_credit_analysis_end_date,
	DATEDIFF(day, nb.init_date, dd12.date)				AS days_init_date_to_credit_analysis_end_date,
	lrf.sk_credit_analysis_approved_date,
	DATEDIFF(day, nb.init_date, dd13.date)				AS days_init_date_to_credit_analysis_approved,
	lrf.sk_contract,
	lrf.sk_contract_created_date,
	DATEDIFF(day, nb.init_date, dd14.date)				AS days_init_date_to_contract_created,
	lrf.sk_contract_signed_date,
	DATEDIFF(day, nb.init_date, dd15.date)				AS days_init_date_to_contract_signed,
	lrf.sk_contract_annulment_date,
	DATEDIFF(day, nb.init_date, dd16.date)				AS days_contract_created_to_contract_annulled,
	lrf.sk_contract_canceled_date,
	DATEDIFF(day, nb.init_date, dd17.date)				AS days_contract_created_to_contract_cancelled,
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