WITH date_base AS (
	SELECT
		sk_date,
		dd.date,
		dd.week_start,
		dd.month_start,
		dd.year_quarter,
		dd.year
	FROM dim_date dd
	WHERE dd.date >= '2019-01-01'
	  AND dd.date <= CURRENT_DATE
	ORDER BY dd.date
	),
	
published_listings AS (	
	SELECT *
	FROM (
        SELECT
            i.id																											AS id_house,
            i.status    																							AS status_history,
            DATE(FROM_UNIXTIME(CAST(rev.timestamp AS BIGINT) / 1000)) AS min_status_date,
            COALESCE(LEAD(DATE(FROM_UNIXTIME(CAST(rev.timestamp AS BIGINT) / 1000)), 1) 
											OVER (PARTITION BY i.id ORDER BY FROM_UNIXTIME(CAST(rev.timestamp AS BIGINT) / 1000)), 
										 DATE('9999-12-31')) 															AS max_status_date
        FROM datalake_raw.ebdb_imovel_AUD i
        LEFT JOIN datalake_raw.ebdb_usuariorevisionentity rev
          ON i.rev = rev.id
        WHERE i.status_mod = 1
        ORDER BY 4
		) base
	WHERE base.status_history = 'publicado'
	),
	
ongoing_listings AS (
	SELECT
		db.date,
		db.week_start,
		db.month_start,
		pl.id_house,
		dhl.sk_house_listing    AS sk_house,
		pl.status_history
	FROM date_base db
	LEFT JOIN published_listings pl
	  ON ((db.date BETWEEN pl.min_status_date AND pl.max_status_date) OR
	  	  (db.date >= pl.min_status_date AND pl.max_status_date IS NULL)
	  	 )
	LEFT JOIN dim_house_listing dhl
	  ON pl.id_house = dhl.id_house
	 AND db.date BETWEEN DATE(dhl.ts_listing_version_start) AND DATE(COALESCE(dhl.ts_listing_version_end, '9999-12-31'))
	GROUP BY db.date,
    		 db.week_start,
    		 db.month_start,
    		 pl.id_house,
			 dhl.sk_house_listing,
    		 pl.status_history
	ORDER BY db.date
	),

newbiz_listings_version AS (

  -- get newbiz listings last flagged version
  SELECT *
  FROM (
    SELECT
      dhl.id_house,
      dhl.sk_house_listing								    AS sk_house_listing,
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
    WHERE (dhl.sk_house_listing LIKE '%000' AND DATE(dhl.ts_listing_version_end) >= newbiz_flg.optedinat)
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
        DATE(dhl.ts_last_de_publication)        AS de_publication_date,
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
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17

    UNION

    -- gets orent info
    SELECT
        dhl.sk_house_listing    										AS sk_house_listing,
        dhl.id_house,
        DATE(dhl.ts_publication)										AS publication_date,
        DATE(dhl.ts_last_de_publication)						AS de_publication_date,
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
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17

    UNION

    -- gets ready info
    SELECT
        dhl.sk_house_listing,
        dhl.id_house,
        DATE(dhl.ts_publication)			AS publication_date,
        DATE(dhl.ts_last_de_publication)   AS de_publication_date,
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
        DATE(dhl.ts_last_de_publication)   AS de_publication_date,
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
	),
	
newbiz_ongoing_listings AS (
	SELECT
		db.date,
		db.week_start,
		db.month_start,
		db.year_quarter,
		db.year,
		base.sk_house_listing,
		base.id_house,
		base.newbiz_type
	FROM date_base db
	LEFT JOIN (
		SELECT
			ol.date,
			ol.week_start,
			ol.month_start,
			nbl.sk_house_listing,
			nbl.id_house,
			nbl.newbiz_type
		FROM ongoing_listings ol
		LEFT JOIN newbiz_listings nbl
		  ON ol.sk_house = nbl.sk_house_listing
		 AND ol.date >= nbl.init_date
		WHERE nbl.sk_house_listing IS NOT NULL
		) base
	  ON db.date = base.date
	ORDER BY db.date,
			 base.sk_house_listing
	),
	
webmetrics AS (
	SELECT
    DATE(regexp_substr(event_time, '\\d{4}-\\d{2}-\\d{2}')) 								AS event_time,
    CAST(json_extract_path_text(event_properties, 'house_id') AS VARCHAR)   AS house_id,
    COUNT(DISTINCT CASE
                    WHEN event_type = 'listing_page_viewed'
                    THEN uuid
                    ELSE NULL
                    END)        AS listing_page_viewed,
    COUNT(DISTINCT CASE
                    WHEN event_type = 'visit_intent_clicked'
                    THEN uuid
                    ELSE NULL
                    END)        AS visit_intent_clicked,
    COUNT(DISTINCT CASE
                    WHEN event_type = 'schedule_page_viewed'
                    THEN uuid
                    ELSE NULL
                    END)        AS schedule_page_viewed
    FROM datalake_amplitude_clean_prod.events
    WHERE event_type IN ('listing_page_viewed', 'visit_intent_clicked', 'schedule_page_viewed')
      AND DATE(regexp_substr(event_time, '\\d{4}-\\d{2}-\\d{2}')) >= '2019-01-01'
    GROUP BY 1, 2
    ORDER BY 1, 2
	),
	
bookings AS (
	SELECT
		dd.date,
		lrf.sk_house_listing,
		COUNT(DISTINCT sk_booking)	AS bookings
	FROM fact_listing_rent_flows lrf
	LEFT JOIN dim_date dd
	  ON lrf.sk_booking_created_date = dd.sk_date
	WHERE lrf.sk_booking_created_date != -1
	  AND dd.date >= '2019-01-01'
	GROUP BY dd.date,
			 lrf.sk_house_listing
	),
	
visits_completed AS (
	SELECT
		dd.date,
		lrf.sk_house_listing,
		COUNT(DISTINCT sk_visit)	AS visits_completed
	FROM fact_listing_rent_flows lrf
	LEFT JOIN dim_date dd
	  ON lrf.sk_visit_date = dd.sk_date
	WHERE lrf.sk_visit_date != -1
	  AND dd.date >= '2019-01-01'
	  AND lrf.flg_visit_completed = true
	GROUP BY dd.date,
			 lrf.sk_house_listing
	),
	
offers_submitted AS (
	SELECT
		dd.date,
		lrf.sk_house_listing,
		COUNT(DISTINCT sk_offer)	AS offers_submitted
	FROM fact_listing_rent_flows lrf
	LEFT JOIN dim_date dd
	  ON lrf.sk_offer_submitted_date = dd.sk_date
	WHERE lrf.sk_offer_submitted_date != -1
	  AND dd.date >= '2019-01-01'
	GROUP BY dd.date,
			 lrf.sk_house_listing
	),

offers_approved AS (
	SELECT
		dd.date,
		lrf.sk_house_listing,
		COUNT(DISTINCT sk_offer)	AS offers_approved
	FROM fact_listing_rent_flows lrf
	LEFT JOIN dim_date dd
	  ON lrf.sk_offer_approved_date = dd.sk_date
	WHERE lrf.sk_offer_approved_date != -1
	  AND dd.date >= '2019-01-01'
	GROUP BY dd.date,
			 lrf.sk_house_listing
	),

proposals_approved AS (
	SELECT
		dd.date,
		lrf.sk_house_listing,
		COUNT(DISTINCT sk_proposal)	AS proposals_approved
	FROM fact_listing_rent_flows lrf
	LEFT JOIN dim_date dd
	  ON lrf.sk_proposal_approved_date = dd.sk_date
	WHERE lrf.sk_proposal_approved_date != -1
	  AND dd.date >= '2019-01-01'
	GROUP BY dd.date,
			 lrf.sk_house_listing
	),

first_doc_sent AS (
	SELECT
		dd.date,
		lrf.sk_house_listing,
		COUNT(DISTINCT sk_tenant_first_doc_sent_date)	AS first_doc_sent
	FROM fact_listing_rent_flows lrf
	LEFT JOIN dim_date dd
	  ON lrf.sk_tenant_first_doc_sent_date = dd.sk_date
	WHERE lrf.sk_tenant_first_doc_sent_date != -1
	  AND dd.date >= '2019-01-01'
	GROUP BY dd.date,
			 lrf.sk_house_listing
	),
	
credit_approved AS (
	SELECT
		dd.date,
		lrf.sk_house_listing,
		COUNT(DISTINCT sk_credit_analysis_approved_date) AS credit_approved
	FROM fact_listing_rent_flows lrf
	LEFT JOIN dim_date dd
	  ON lrf.sk_credit_analysis_approved_date = dd.sk_date
	WHERE lrf.sk_credit_analysis_approved_date != -1
	  AND dd.date >= '2019-01-01'
	GROUP BY dd.date,
			 lrf.sk_house_listing
	),
	
contract_created AS (
	SELECT
		dd.date,
		lrf.sk_house_listing,
		COUNT(DISTINCT sk_contract) AS contract_created
	FROM fact_listing_rent_flows lrf
	LEFT JOIN dim_date dd
	  ON lrf.sk_contract_created_date = dd.sk_date
	WHERE lrf.sk_contract_created_date != -1
	  AND dd.date >= '2019-01-01'
	GROUP BY dd.date,
			 lrf.sk_house_listing
	),
	
contract_signed AS (
	SELECT
		dd.date,
		lrf.sk_house_listing,
		COUNT(DISTINCT sk_contract) AS contract_signed
	FROM fact_listing_rent_flows lrf
	LEFT JOIN dim_date dd
	  ON lrf.sk_contract_signed_date = dd.sk_date
	WHERE lrf.sk_contract_signed_date != -1
	  AND dd.date >= '2019-01-01'
	GROUP BY dd.date,
			 lrf.sk_house_listing
	)
	
SELECT
	nol.date,
	nol.week_start,
	nol.month_start,
	nol.year_quarter,
	nol.year,
	nol.sk_house_listing,
	nol.newbiz_type,
	COALESCE(w.listing_page_viewed, 0)			AS listing_page_viewed,
	COALESCE(w.visit_intent_clicked, 0)			AS visit_intent_clicked,
	COALESCE(w.schedule_page_viewed, 0)			AS schedule_page_viewed,
	COALESCE(b.bookings, 0)									AS bookings,
	COALESCE(vc.visits_completed, 0)				AS visits_completed,
	COALESCE(os.offers_submitted, 0)				AS offers_submitted,
	COALESCE(oa.offers_approved, 0)					AS offers_approved,
	COALESCE(pa.proposals_approved, 0)			AS proposals_approved,
	COALESCE(fds.first_doc_sent, 0)					AS first_doc_sent,
	COALESCE(ca.credit_approved, 0)					AS credit_approved,
	COALESCE(cc.contract_created, 0)				AS contract_created,
	COALESCE(cs.contract_signed, 0)					AS contract_signed
FROM newbiz_ongoing_listings nol
LEFT JOIN webmetrics w
  ON nol.date = w.event_time
 AND nol.id_house = house_id
LEFT JOIN bookings b
  ON nol.date = b.date
 AND nol.sk_house_listing = b.sk_house_listing
LEFT JOIN visits_completed vc
  ON nol.date = vc.date
 AND nol.sk_house_listing = vc.sk_house_listing
LEFT JOIN offers_submitted os
  ON nol.date = os.date
 AND nol.sk_house_listing = os.sk_house_listing
LEFT JOIN offers_approved oa
  ON nol.date = oa.date
 AND nol.sk_house_listing = oa.sk_house_listing
LEFT JOIN proposals_approved pa
  ON nol.date = pa.date
 AND nol.sk_house_listing = pa.sk_house_listing
LEFT JOIN first_doc_sent fds
  ON nol.date = fds.date
 AND nol.sk_house_listing = fds.sk_house_listing
LEFT JOIN credit_approved ca
  ON nol.date = ca.date
 AND nol.sk_house_listing = ca.sk_house_listing
LEFT JOIN contract_created cc
  ON nol.date = cc.date
 AND nol.sk_house_listing = cc.sk_house_listing
LEFT JOIN contract_signed cs
  ON nol.date = cs.date
 AND nol.sk_house_listing = cs.sk_house_listing
WHERE nol.sk_house_listing NOT LIKE '%000'
ORDER BY nol.date,
		 nol.sk_house_listing
 ;