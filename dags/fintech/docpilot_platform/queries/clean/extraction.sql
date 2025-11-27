SELECT
	id,
	document_id AS id_document,
	extractor_name,
	document_extractor_type,
	extracted_data,
	extractor_metadata,
	error,
	created_at AS ts_created,
	status,
	processed_at AS ts_processed,
	retry_count AS retry_count
FROM datalake_docpilot_platform_raw.extraction
