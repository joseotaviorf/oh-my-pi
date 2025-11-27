SELECT
	id,
	document_external_id AS id_document_external,
	context,
	application_name,
	original_document_uri,
	internal_document_uri,
	document_metadata,
	checksum,
	created_at AS ts_created
FROM datalake_docpilot_platform_raw.document
