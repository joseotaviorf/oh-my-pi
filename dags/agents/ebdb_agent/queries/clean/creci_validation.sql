SELECT
    id,
    creci_validation_uuid AS uuid_creci_validation,
    person_uuid AS uuid_person,
    legal_entity_type,
    validation_input_hash,
    version,
    status,
    reason,
    provider,
    validated_at AS ts_validated,
    reusable_until AS ts_reusable_until,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.CreciValidation
