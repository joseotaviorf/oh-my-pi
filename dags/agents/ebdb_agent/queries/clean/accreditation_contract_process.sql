SELECT
    id,
    qualification_id AS id_qualification,
    contract_template_id AS id_contract_template,
    replaced_process_id AS id_replaced_process,
    contract_process_uuid AS uuid_contract_process,
    status,
    unsigned_document_s3_key,
    author_type,
    author_identifier,
    initiated_at AS ts_initiated,
    finished_at AS ts_finished,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.AccreditationContractProcess 