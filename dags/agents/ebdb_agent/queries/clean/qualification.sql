SELECT
    id,
    agent_prospect_id AS id_agent_prospect,
    qualification_template_id AS id_qualification_template,
    author_identifier AS id_author_identifier,
    qualification_uuid AS uuid_qualification,
    reason,
    state,
    author_type,
    rejected_at AS ts_rejected,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.qualification