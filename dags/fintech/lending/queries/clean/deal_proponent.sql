SELECT
    id,
    deal_id AS id_deal,
    person_uuid AS uuid_person,
    user_id AS id_user,
    name,
    cpf,
    email,
    phone,
    address,
    address_number,
    complement,
    neighborhood,
    city,
    state,
    cep,
    birth_date AS dt_birth,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_lending_raw.deal_proponent
