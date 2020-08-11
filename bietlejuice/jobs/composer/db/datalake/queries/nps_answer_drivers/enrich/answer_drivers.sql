WITH house_contract_tags AS (
	SELECT
                id_answer,
                ts_answer_sent,
                MAX(CASE WHEN tag_name <> 'Contrato' THEN CAST(tag_value AS BIGINT) END) AS id_house,
		MAX(CASE WHEN tag_name = 'Contrato' THEN CAST(tag_value AS BIGINT) END) AS id_contract
	FROM datalake_tracksale.answer_tags
	WHERE tag_name IN ('Cu00f3d do imu00f3vel','Cód Imóvel','Cód do imóvel','Contrato')
	GROUP BY 1,2
),
driver_tags AS (
	SELECT
		at1.id_answer,
		at1.ts_answer_sent,
		CAST((CASE WHEN at1.tag_value = 'house_listing' THEN at2.tag_value END) AS BIGINT) AS id_house_listing,
		CAST((CASE WHEN at1.tag_value = 'booking' THEN at2.tag_value END) AS BIGINT) AS id_booking,
		CASE WHEN at1.tag_value = 'talk to agent' THEN at2.tag_value END AS id_tta,
		CAST((CASE WHEN at1.tag_value = 'offer' THEN at2.tag_value END) AS BIGINT) AS id_offer_context, -- this comes in Tracksale as sk_offer rather than id_offer from EBDB
		CAST((CASE WHEN at1.tag_value IN ('contract', 'sk_contract') THEN at2.tag_value END) AS BIGINT) AS id_contract
	FROM datalake_tracksale.answer_tags at1
	INNER JOIN datalake_tracksale.answer_tags at2
		ON at1.id_answer = at2.id_answer
	WHERE at1.tag_name = 'Driver'
		AND at2.tag_name = 'Driver Id'
),
combined_drivers AS (
	SELECT
		COALESCE(dt.id_answer,hct.id_answer) AS id_answer,
		hct.id_house,
		dt.id_house_listing,
		dt.id_booking,
		dt.id_tta,
		dt.id_offer_context,
		COALESCE(dt.id_contract,hct.id_contract) AS id_contract,
		COALESCE(dt.ts_answer_sent, hct.ts_answer_sent) AS ts_answer_sent
	FROM driver_tags dt
	FULL JOIN house_contract_tags hct
		ON hct.id_answer = dt.id_answer
),
ebdb_house AS (
	SELECT
		cd.id_answer,
		cd.ts_answer_sent,
		COALESCE(lh.id,sh.id) AS id_house
	FROM combined_drivers cd
	LEFT JOIN datalake_ebdb_clean.house lh
		ON lh.id = cd.id_house
	LEFT JOIN datalake_ebdb_clean.house sh -- recovering input data as short ID house
		ON sh.id % 892700000 = cd.id_house
	WHERE lh.id IS NOT NULL
		OR sh.id IS NOT NULL
),
ebdb_house_listing AS (
	SELECT
		eh.id_answer,
		eh.ts_answer_sent,
		MAX(hl.id_house_listing) AS id_house_listing -- preventing duplicates if ts_answer_sent is right at versioning transition
	FROM ebdb_house eh
	INNER JOIN datalake_ebdb_listing.house_listing hl
		ON hl.id_house = eh.id_house
	WHERE eh.ts_answer_sent >= hl.ts_listing_version_start
		AND eh.ts_answer_sent <= hl.ts_listing_version_end
	GROUP BY 1,2
),
listing_drivers AS (
	SELECT
		cd.id_answer,
		COALESCE(cd.id_house_listing, ehl.id_house_listing) AS id_house_listing
	FROM combined_drivers cd
	LEFT JOIN ebdb_house_listing ehl
		ON cd.id_answer = ehl.id_answer
),
ebdb_listing AS (
	SELECT 
		ld.id_answer,
		ld.id_house_listing
	FROM listing_drivers ld 
	INNER JOIN datalake_ebdb_listing.house_listing hl 
		ON hl.id_house_listing = ld.id_house_listing
),
ebdb_booking AS (
	SELECT
		cd.id_answer,
		cd.id_booking
	FROM combined_drivers cd
	INNER JOIN datalake_ebdb_clean.booking b 
		ON b.id = cd.id_booking
),
unmounted_offers AS (
	SELECT 
        id_answer,
        id_offer_context,
        CASE WHEN SUBSTRING(CAST(id_offer_context AS STRING),-1,1) = '2' THEN (id_offer_context - 2)/100.0
            END AS id_offer -- converting sk_offer to id_offer to validate values at EBDB
    FROM driver_tags
),
ebdb_offer AS (
	SELECT
		uo.id_answer,
		uo.id_offer_context
	FROM unmounted_offers uo
	INNER JOIN datalake_ebdb_clean.offer o
		ON o.id = uo.id_offer
),
ebdb_contract AS (
	SELECT 
		cd.id_answer,
		cd.id_contract
	FROM combined_drivers cd
	INNER JOIN datalake_ebdb_clean.contract c 
	  ON c.id = cd.id_contract
)
SELECT 
	a.id AS id_answer,
	el.id_house_listing,
	eb.id_booking,
	cd.id_tta,
	eo.id_offer_context,
	ec.id_contract
FROM datalake_tracksale.answer a
LEFT JOIN combined_drivers cd 
	ON cd.id_answer = a.id
LEFT JOIN ebdb_listing el 
	ON el.id_answer = cd.id_answer
LEFT JOIN ebdb_booking eb 
	ON eb.id_answer = cd.id_answer
LEFT JOIN ebdb_offer eo 
	ON eo.id_answer = cd.id_answer
LEFT JOIN ebdb_contract ec 
	ON ec.id_answer = cd.id_answer
WHERE COALESCE(el.id_house_listing, eb.id_booking, cd.id_tta, eo.id_offer_context, ec.id_contract) IS NOT NULL
