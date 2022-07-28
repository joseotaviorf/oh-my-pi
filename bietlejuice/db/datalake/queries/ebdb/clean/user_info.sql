select
    id,
    atualizadoEm as ts_updated,
    criadoEm as ts_created,
    user_id as id_user,
    name,
    email,
    phone as phone_number,
    cpf,
    rg,
    cnpj,
    personType as person_type,
    address,
    number,
    complement,
    zipCode as zip_code,
    neighborhood,
    city,
    state_id as id_state,
    letterOfAttorneyFilename as letter_of_attorney_file_name
from
    datalake_ebdb_raw.userinfo