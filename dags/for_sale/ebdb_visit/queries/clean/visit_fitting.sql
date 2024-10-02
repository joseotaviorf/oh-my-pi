SELECT
    id,
    fitted_visit_id AS id_visit,
    visitor_id AS id_visitor,
    house_id AS id_house,
    begin_slot,
    end_slot,
    business_context,
    intention,
    status,
    channel,
    request_context,
    visit_date AS dt_visit,
    expiration_date AS ts_expiration,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_test_raw.VisitFitting

