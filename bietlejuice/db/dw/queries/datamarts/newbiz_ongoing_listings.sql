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
					hs.sk_house,
					hs.status_history,
					hs.sk_min_status_date,
					COALESCE(LEAD(hs.sk_min_status_date, 1) OVER (PARTITION BY hs.sk_house ORDER BY hs.sk_min_status_date), 99999999)   AS sk_max_status_date
			FROM fact_house_status hs
			ORDER BY hs.sk_min_status_date
		) base
	WHERE base.status_history = 'publicado'
	),
	
ongoing_listings AS (
	SELECT
		db.date,
		db.week_start,
		db.month_start,
		pl.sk_house,
		pl.status_history
	FROM date_base db
	LEFT JOIN published_listings pl
	  ON ((db.sk_date BETWEEN pl.sk_min_status_date AND pl.sk_max_status_date) OR
	  	  (db.sk_date >= pl.sk_min_status_date AND pl.sk_max_status_date IS NULL)
	  	 )
	GROUP BY db.date,
    		 db.week_start,
    		 db.month_start,
    		 pl.sk_house,
    		 pl.status_history
	ORDER BY db.date
	),
	
newbiz_listings AS (
	SELECT 
		base.sk_house_listing,
		base.id_house,
		base.init_date,
		CASE
			WHEN base.is_orent = true
			THEN 'oRent'
			WHEN base.is_irent = true
			THEN 'iRent'
			ELSE base.last_originals_type
			END													AS type,	
		base.dt_last_originals_opted_out
	FROM (
		-- gets renos info
		SELECT
			dhl.sk_house_listing,
			dhl.id_house,
			False																		AS is_orent,
			False																		AS is_irent,
			dhl.last_originals_type,
			dhl.dt_last_originals_opted_out,
			MIN(DATE(fpj.sk_date_photos_uploaded))	AS date_job_photos_uploaded,
			MIN(DATE(ei.atualizadoem))							AS date_photos_uploaded,
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
				END init_date
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
		GROUP BY 1, 2, 3, 4, 5, 6

		UNION

		-- gets orent info
		SELECT
			MAX(dhl.sk_house_listing)								AS sk_house_listing,
			dhl.id_house,
			True																		AS is_orent,
			False																		AS is_irent,
			dhl.last_originals_type,
			dhl.dt_last_originals_opted_out,
			MIN(DATE(fpj.sk_date_photos_uploaded))	AS date_job_photos_uploaded,
			MIN(DATE(ei.atualizadoem))							AS date_photos_uploaded,
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
				END																		AS init_date
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
		GROUP BY 2, 3, 4, 5, 6

		UNION

		-- gets ready info
		SELECT
			dhl.sk_house_listing,
			dhl.id_house,
			False															AS is_orent,
			False															AS is_irent,
			dhl.last_originals_type,
			dhl.dt_last_originals_opted_out,
			DATE(NULL)												AS date_job_photos_uploaded,
			DATE(NULL)												AS date_photos_uploaded,
			DATE(dhl.ts_publication)					AS init_date	
    FROM dim_house_listing dhl
    JOIN (SELECT
            -- max published listing before last originals optedin date
            dhl.id_house,
            MAX(dhl.sk_house_listing)	AS sk_house_listing
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
			MAX(dhl.sk_house_listing)					AS sk_house_listing,
			dhl.id_house,
			False															AS is_orent,
			True															AS is_irent,
			dhl.last_originals_type,
			dhl.dt_last_originals_opted_out,
			DATE(NULL)												AS date_job_photos_uploaded,
			DATE(NULL)												AS date_photos_uploaded,
			DATE(dhl.ts_publication)					AS init_date
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
		GROUP BY 2, 3, 4, 5, 6, 7, 8, 9
		) base
	WHERE base.init_date IS NOT NULL
	ORDER BY base.sk_house_listing
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
		base.type
	FROM date_base db
	LEFT JOIN (
		SELECT
			ol.date,
			ol.week_start,
			ol.month_start,
			nbl.sk_house_listing,
			nbl.id_house,
			nbl.type
		FROM ongoing_listings ol
		LEFT JOIN newbiz_listings nbl
		  ON ol.sk_house = nbl.sk_house_listing
		 AND ol.date >= nbl.init_date
		 AND (ol.date <= dt_last_originals_opted_out OR
		      dt_last_originals_opted_out IS NULL)
		WHERE nbl.sk_house_listing IS NOT NULL
		) base
	  ON db.date = base.date
	ORDER BY db.date,
			 base.sk_house_listing
	),
	
webmetrics AS (		
	SELECT
		DATE(event_time),
		TRIM(e_house_id) 			AS house_id,
		COUNT(DISTINCT CASE
						WHEN TRIM(et) = 'listing_page_viewed'
						THEN uuid
						ELSE NULL
						END)		AS listing_page_viewed,
		COUNT(DISTINCT CASE
						WHEN TRIM(et) = 'visit_intent_clicked'
						THEN uuid
						ELSE NULL
						END)		AS visit_intent_clicked,
		COUNT(DISTINCT CASE
						WHEN TRIM(et) = 'schedule_page_viewed'
						THEN uuid
						ELSE NULL
						END)		AS schedule_page_viewed
	FROM datalake_clean.amplitude_events
	WHERE TRIM(et) IN ('listing_page_viewed', 'visit_intent_clicked', 'schedule_page_viewed')
	  AND DATE(event_time) >= '2019-01-01'
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
	nol.type,
	COALESCE(w.listing_page_viewed, 0)				AS listing_page_viewed,
	COALESCE(w.visit_intent_clicked, 0)				AS visit_intent_clicked,
	COALESCE(w.schedule_page_viewed, 0)				AS schedule_page_viewed,
	COALESCE(b.bookings, 0)							AS bookings,
	COALESCE(vc.visits_completed, 0)				AS visits_completed,
	COALESCE(os.offers_submitted, 0)				AS offers_submitted,
	COALESCE(oa.offers_approved, 0)					AS offers_approved,
	COALESCE(pa.proposals_approved, 0)				AS proposals_approved,
	COALESCE(fds.first_doc_sent, 0)					AS first_doc_sent,
	COALESCE(ca.credit_approved, 0)					AS credit_approved,
	COALESCE(cc.contract_created, 0)				AS contract_created,
	COALESCE(cs.contract_signed, 0)					AS contract_signed
FROM newbiz_ongoing_listings nol
LEFT JOIN webmetrics w
  ON nol.date = w.date
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
ORDER BY nol.date,
		 nol.sk_house_listing
 ;