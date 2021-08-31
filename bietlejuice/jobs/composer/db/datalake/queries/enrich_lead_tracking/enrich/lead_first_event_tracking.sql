WITH t_union AS (
	SELECT
		lo_external_id.*,
		l.id AS id_from_lead
	FROM datalake_ebdb_clean.lead l
	JOIN datalake_amplitude_lead.lead_origin lo_external_id
	    ON lo_external_id.formfield_lead_uuid =  l.id_external
	    AND lo_external_id.formfield_lead_uuid IS NOT NULL
    UNION ALL
	SELECT
		lo_firestore_id.*,
		l.id AS id_from_lead
	FROM datalake_ebdb_clean.lead l
	JOIN datalake_amplitude_lead.lead_origin lo_firestore_id
	    ON lo_firestore_id.id_firestore =  l.id_external
	    AND lo_firestore_id.id_firestore IS NOT NULL
    UNION ALL
	SELECT
		lo_lead_id.*,
		l.id AS id_from_lead
	FROM datalake_ebdb_clean.lead l
	JOIN datalake_amplitude_lead.lead_origin lo_lead_id
	    ON lo_lead_id.id_lead =  l.id
	    AND lo_lead_id.id_lead IS NOT NULL
),
t_rn AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_from_lead ORDER BY rule_num DESC) AS lead_rn
    FROM t_union
)
SELECT
	id_from_lead AS id_lead,
	REGEXP_REPLACE(utm_campaign,'[^\x00-\x7F^ÁáÂâÃãÉéÊêÍíÓóÔôÕõÚúÇçÀà]+', '') AS tracking_campaign,
	REGEXP_REPLACE(utm_medium,'[^\x00-\x7F^ÁáÂâÃãÉéÊêÍíÓóÔôÕõÚúÇçÀà]+', '') AS tracking_medium,
	REGEXP_REPLACE(utm_source,'[^\x00-\x7F^ÁáÂâÃãÉéÊêÍíÓóÔôÕõÚúÇçÀà]+', '') AS tracking_source,
	REGEXP_REPLACE(utm_content,'[^\x00-\x7F^ÁáÂâÃãÉéÊêÍíÓóÔôÕõÚúÇçÀà]+', '') AS tracking_content,
	REGEXP_REPLACE(utm_term,'[^\x00-\x7F^ÁáÂâÃãÉéÊêÍíÓóÔôÕõÚúÇçÀà]+', '') AS tracking_term,
	REGEXP_REPLACE(platform,'[^\x00-\x7F^ÁáÂâÃãÉéÊêÍíÓóÔôÕõÚúÇçÀà]+', '') AS tracking_platform,
	REGEXP_REPLACE(referring_domain,'[^\x00-\x7F^ÁáÂâÃãÉéÊêÍíÓóÔôÕõÚúÇçÀà]+', '') AS tracking_referring_domain,
	REGEXP_REPLACE(region,'[^\x00-\x7F^ÁáÂâÃãÉéÊêÍíÓóÔôÕõÚúÇçÀà]+', '') AS tracking_region,
	REGEXP_REPLACE(city,'[^\x00-\x7F^ÁáÂâÃãÉéÊêÍíÓóÔôÕõÚúÇçÀà]+', '') AS tracking_city
FROM t_rn
WHERE id_from_lead IS NOT NULL
      AND lead_rn = 1