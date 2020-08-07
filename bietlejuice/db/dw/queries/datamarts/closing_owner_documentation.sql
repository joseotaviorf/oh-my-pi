WITH documents AS (
SELECT
	fr.target_folder_id AS house_folder_id, 
	tf.external_id AS house_id, 
	sf.id AS part_folder_id, 
	sf.external_id AS user_id,
	sft.name AS type_name, 
	fr.id AS folder_reference_id, 
	frt.name AS ref_name, 
	d.id AS document_id, 
	dt.name AS document_name, 
	d.ATTRIBUTES,
	CASE WHEN sft.name = 'COMPANY' 
		AND dt.name = 'REPRESENTED_DATA'  THEN JSON_EXTRACT_PATH_TEXT(d.attributes,'cnpj')
	WHEN sft.name IN ('PERSON','USER') 
		AND dt.name = 'PERSONAL_DATA' THEN JSON_EXTRACT_PATH_TEXT(d.attributes,'cpf') 
	ELSE '-1'
	END AS person_id,
	tf.created_at::timestamp AS ts_target_folder_created,
	sf.created_at::timestamp AS ts_source_folder_created,
	d.created_at::timestamp AS ts_document_created
FROM datalake_docx_raw_prod.document d
INNER JOIN datalake_docx_raw_prod.document_type dt 
	ON dt.id = d.document_type_id
INNER JOIN datalake_docx_raw_prod.folder_reference fr 
	ON fr.source_folder_id = d.folder_id
INNER JOIN datalake_docx_raw_prod.folder_reference_type frt 
	ON frt.id = fr.folder_reference_type_id
INNER JOIN datalake_docx_raw_prod.folder sf 
	ON fr.source_folder_id = sf.id
INNER JOIN datalake_docx_raw_prod.folder_type sft 
	ON sf.folder_type_id = sft.id
INNER JOIN datalake_docx_raw_prod.folder tf 
	ON fr.target_folder_id = tf.id 
), docs AS (
SELECT
	house_folder_id, 
	house_id,
	part_folder_id, 
	user_id, 
	folder_reference_id,
	type_name,
	ref_name AS ref_name,
	CASE
	WHEN ref_name = 'MAIN_OWNER'
		OR (ref_name = 'OWNER'
		AND type_name = 'USER')THEN 'single_owner'
	WHEN (ref_name = 'OWNER'
		AND type_name = 'COMPANY')
		OR ref_name = 'COMPANY_REPRESENTATIVE' THEN 'company_representative'
	WHEN (ref_name = 'OWNER'
		AND type_name = 'PERSON')
		OR ref_name = 'PERSON_REPRESENTATIVE' THEN 'person_representative'
	WHEN ref_name = 'MULTIPLE_OWNER' THEN 'multiple_owner'
	ELSE 'other'
	END AS house_owner_type, 
	ts_target_folder_created, 
	ts_source_folder_created, 
	MIN(ts_document_created) AS ts_first_doc_created, 
	MAX(ts_document_created) AS ts_last_doc_created, 
	SUM(CASE WHEN document_name = 'RG' THEN 1 ELSE 0 END) AS RG, 
	SUM(CASE WHEN document_name = 'CPF' THEN 1 ELSE 0 END) AS CPF, 
	SUM(CASE WHEN document_name = 'CNH' THEN 1 ELSE 0 END) AS CNH, 
	SUM(CASE WHEN document_name = 'RNE' THEN 1 ELSE 0 END) AS RNE, 
	SUM(CASE WHEN document_name = 'PERSONAL_DATA' THEN 1 ELSE 0 END) AS PERSONAL_DATA, 
	SUM(CASE WHEN document_name = 'BILLING_ADDRESS' THEN 1 ELSE 0 END) AS BILLING_ADDRESS, 
	SUM(CASE WHEN document_name = 'BANK_DATA' THEN 1 ELSE 0 END) AS BANK_DATA, 
	SUM(CASE WHEN document_name = 'PROPERTY_TAX' THEN 1 ELSE 0 END) AS PROPERTY_TAX, 
	SUM(CASE WHEN document_name = 'REPRESENTED_DATA' THEN 1 ELSE 0 END) AS REPRESENTED_DATA, 
	SUM(CASE WHEN document_name = 'POWER_OF_ATTORNEY' THEN 1 ELSE 0 END) AS POWER_OF_ATTORNEY
FROM documents
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 
), parts_count AS(
SELECT
	house_id, 
	count(DISTINCT folder_reference_id) AS parts_count
FROM docs
GROUP BY 1 
), docs_complete AS(
SELECT
	house_folder_id, 
	d.house_id, 
	house_owner_type, 
	part_folder_id, 
	user_id, 
	type_name AS client_type, 
	ref_name,
	CASE WHEN (ref_name = 'MAIN_OWNER'
		OR (ref_name = 'OWNER'
		AND type_name = 'USER'))
		AND (RG >0
		OR CNH >0
		OR RNE >0)
		AND PERSONAL_DATA >0
		AND BILLING_ADDRESS >0
		AND BANK_DATA >0 THEN 'MAIN_OWNER_COMPLETE'
	WHEN ref_name = 'PERSON_REPRESENTATIVE'
		AND (RG >0
		OR CNH >0
		OR RNE >0)
		AND PERSONAL_DATA >0
		AND BILLING_ADDRESS >0
		AND BANK_DATA >0 THEN 'PERSON_REPRESENTATIVE_COMPLETE'
	WHEN ref_name = 'COMPANY_REPRESENTATIVE'
		AND RG >0
		AND PERSONAL_DATA >0
		AND BILLING_ADDRESS >0
		AND BANK_DATA >0 THEN 'COMPANY_REPRESENTATIVE_COMPLETE'
	WHEN ((ref_name = 'OWNER'
		AND type_name = 'PERSON')
		OR (ref_name = 'OWNER'
		AND type_name = 'COMPANY'))
		AND REPRESENTED_DATA >0
		AND POWER_OF_ATTORNEY >0 THEN 'OWNER_REP_COMPLETE'
	WHEN ref_name = 'MULTIPLE_OWNER'
		AND (RG >0
		OR CNH >0
		OR RNE >0)
		AND PERSONAL_DATA >0
		AND BILLING_ADDRESS >0
		AND BANK_DATA >0 THEN 'MAIN_MULTIPLE_OWNER_COMPLETE'
	WHEN ref_name = 'MULTIPLE_OWNER'
		AND (RG >0
		OR CNH >0
		OR RNE >0)
		AND PERSONAL_DATA >0
		AND BILLING_ADDRESS >0
		AND BANK_DATA IS NULL THEN 'MULTIPLE_OWNER_COMPLETE'
	ELSE 'not_complete'
	END AS part_docs,
	parts_count,
	ts_target_folder_created,
	ts_source_folder_created,
	ts_first_doc_created,
	ts_last_doc_created,
	SUM(CASE WHEN (ref_name = 'MAIN_OWNER' OR (ref_name = 'OWNER' AND type_name = 'USER')) AND (RG >0 OR CNH >0 OR RNE >0) AND PERSONAL_DATA >0 AND BILLING_ADDRESS >0 AND BANK_DATA >0 THEN 1 ELSE 0 END) AS MAIN_OWNER_COMPLETE,
	SUM(CASE WHEN ref_name = 'PERSON_REPRESENTATIVE' AND (RG >0 OR CNH >0 OR RNE >0) AND PERSONAL_DATA >0 AND BILLING_ADDRESS >0 AND BANK_DATA >0 THEN 1 ELSE 0 END) AS PERSON_REPRESENTATIVE_COMPLETE,
	SUM(CASE WHEN ref_name = 'COMPANY_REPRESENTATIVE' AND RG >0 AND PERSONAL_DATA >0 AND BILLING_ADDRESS >0 AND BANK_DATA >0 THEN 1 ELSE 0 END) AS COMPANY_REPRESENTATIVE_COMPLETE,
	SUM(CASE WHEN ((ref_name = 'OWNER' AND type_name = 'PERSON') OR (ref_name = 'OWNER' AND type_name = 'COMPANY')) AND REPRESENTED_DATA >0 AND POWER_OF_ATTORNEY >0 THEN 1 ELSE 0 END) AS OWNER_REP_COMPLETE,
	SUM(CASE WHEN ref_name = 'MULTIPLE_OWNER' AND (RG >0 OR CNH >0 OR RNE >0) AND PERSONAL_DATA >0 AND BILLING_ADDRESS >0 AND BANK_DATA > 0 THEN 1 ELSE 0 END) AS MAIN_MULTIPLE_OWNER_COMPLETE,
	SUM(CASE WHEN ref_name = 'MULTIPLE_OWNER' AND (RG >0 OR CNH >0 OR RNE >0) AND PERSONAL_DATA >0 AND BILLING_ADDRESS >0 AND BANK_DATA =0 THEN 1 ELSE 0 END) AS MULTIPLE_OWNER_COMPLETE
FROM docs d
INNER JOIN parts_count pc
	ON pc.house_id = d.house_id
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
), parts_completion AS (
SELECT
	d.house_id,
	house_owner_type,
	parts_count,
	MIN(ts_source_folder_created) AS first_folder_created,
	SUM(MAIN_OWNER_COMPLETE) AS MAIN_OWNER_COMPLETE,
	SUM(PERSON_REPRESENTATIVE_COMPLETE) AS PERSON_REPRESENTATIVE_COMPLETE,
	SUM(COMPANY_REPRESENTATIVE_COMPLETE) AS COMPANY_REPRESENTATIVE_COMPLETE,
	SUM(OWNER_REP_COMPLETE) AS OWNER_REP_COMPLETE,
	SUM(MAIN_MULTIPLE_OWNER_COMPLETE) AS MAIN_MULTIPLE_OWNER_COMPLETE,
	SUM(MULTIPLE_OWNER_COMPLETE) AS MULTIPLE_OWNER_COMPLETE
FROM docs_complete d
GROUP BY 1, 2, 3
), houses_complete AS (
SELECT
	house_id,
	house_owner_type,
	CASE WHEN pc.house_owner_type = 'single_owner'
			AND pc.MAIN_OWNER_COMPLETE = 1 THEN 'single_owner_complete'
		WHEN pc.house_owner_type = 'person_representative'
			AND pc.OWNER_REP_COMPLETE = 1
			AND pc.PERSON_REPRESENTATIVE_COMPLETE = 1 THEN 'person_representative_complete'
		WHEN pc.house_owner_type = 'company_representative'
			AND pc.OWNER_REP_COMPLETE = 1
			AND pc.COMPANY_REPRESENTATIVE_COMPLETE = 1 THEN 'company_representative_complete'
		WHEN pc.house_owner_type = 'multiple_owner'
			AND pc.MAIN_MULTIPLE_OWNER_COMPLETE = 1
			AND pc.MULTIPLE_OWNER_COMPLETE = parts_count-1 THEN 'multiple_complete'
	ELSE 'not_complete'
	END AS docs_complete
FROM parts_completion pc
), single_docs AS (
SELECT
	house_id,
	part_folder_id,
	document_id,
	person_id,
	document_name,
	ts_document_created,
	type_name
FROM documents
), person_id AS (
SELECT
	d.part_folder_id,
	person_id
FROM single_docs d
WHERE person_id <> '-1'
GROUP BY 1, 2)
,listings AS (
SELECT
	hl.id_house,
	hl.sk_house_listing,
	hl.ts_publication AS ts_listing_publication,
	hl.status,
	hl.version,
	MIN(dd.date) AS dt_first_offer_approved
FROM dim_house_listing hl
INNER JOIN fact_listing_rent_flows rf
	ON hl.sk_house_listing = rf.sk_house_listing
INNER JOIN dim_date dd
	ON dd.sk_date = rf.sk_offer_approved_date
GROUP BY 1,2,3,4,5
),docs_started AS (
SELECT
	pid.person_id,
	d.house_folder_id,
	d.house_id,
	d.part_folder_id,
	d.user_id,
	sd.document_id,
	d.house_owner_type,
	d.client_type,
	sd.document_name,
	h.docs_complete,
	d.part_docs,
	d.parts_count,
	d.ts_target_folder_created,
	d.ts_source_folder_created,
	d.ts_first_doc_created,
	d.ts_last_doc_created,
	sd.ts_document_created
FROM docs_complete d
INNER JOIN houses_complete h
 	ON h.house_id = d.house_id
INNER  JOIN single_docs sd
	ON sd.house_id = h.house_id
	AND sd.part_folder_id = d.part_folder_id
LEFT JOIN person_id pid
	ON pid.part_folder_id = sd.part_folder_id)
SELECT
	l.sk_house_listing,
	coalesce(d.person_id, '-1') AS sk_personal_document,
	coalesce(d.user_id, '-1') AS sk_user,
	l.id_house,
	l.version AS listing_version,
	l.status AS listing_status,
	d.house_folder_id AS id_house_folder,
	d.part_folder_id AS id_part_folder,
	d.document_id AS id_document,
	d.house_owner_type AS house_ownership_type,
	d.client_type,
	d.document_name AS document_type,
	(d.ts_target_folder_created IS NOT NULL) AS is_house_documentation_started,
	(d.docs_complete != 'not_complete') AS is_house_documentation_complete,
	(d.part_docs != 'not_complete') AS is_part_folder_complete,
	(l.dt_first_offer_approved IS NOT NULL) AS has_house_offer_approved,
	d.parts_count AS number_of_parts,
	l.dt_first_offer_approved,
	l.ts_listing_publication,
	d.ts_target_folder_created AS ts_house_folder_created,
	d.ts_source_folder_created AS ts_part_folder_created,
	d.ts_first_doc_created,
	d.ts_last_doc_created,
	d.ts_document_created,
	current_timestamp as ts_load
FROM listings l
LEFT JOIN docs_started d
	ON l.id_house=d.house_id
