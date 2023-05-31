SELECT 
	id,
	house_lead_id AS id_lead,
	property_id AS id_house,
	rev,
	revtype AS rev_type,
	revend AS rev_end,
	created_at AS ts_created,
	updated_at AS ts_updated,
	year,
	month,
	day
FROM
	datalake_rene_descartes_raw.house_lead_conversion_aud
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id, rev ORDER BY dt DESC) = 1    