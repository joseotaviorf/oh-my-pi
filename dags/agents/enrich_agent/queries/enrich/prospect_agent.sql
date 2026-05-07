SELECT
    pa.id AS id_prospect_agent,
    a.id AS id_agent,
    IF(qapa.primary_operating_region_type = 'HUB', qapa.id_primary_operating_region, NULL) AS id_business_unit,
    IF(qapa.parent_operating_region_type = 'REGION', qapa.id_parent_operating_region, NULL) AS id_region,
    pa.uuid_prospect,
    pa.uuid_person,
    pa.legal_entity_type,
    pa.status,
    pa.business_association,
    qapa.business_context_of_interest AS business_context_applied,
    pa.quintoandar_knowledge,
    pa.social,
    qapa.creci,
    qapa.creci_uf,
    qapa.is_available_on_weekends,
    qapa.is_accepted_alternative_context,
    qapa.is_accepted_alternative_region,
    pa.ts_created,
    pa.ts_updated
FROM
    datalake_ebdb_clean.prospect_agent AS pa
LEFT JOIN
    datalake_ebdb_clean.agent AS a
        ON a.uuid_person = pa.uuid_person
LEFT JOIN
    datalake_ebdb_clean.quintoandar_prospect_agent AS qapa
        ON qapa.id_prospect_agent = pa.id