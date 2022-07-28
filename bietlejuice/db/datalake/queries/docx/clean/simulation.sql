SELECT
    id,
    simulation_user_id AS id_simulation_user,
    version,
    simulation_version,
    sharing_option,
    result,
    max_package,
    calculated_at AS ts_calculated,
    queried_at AS ts_queried,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_docx_raw.simulation