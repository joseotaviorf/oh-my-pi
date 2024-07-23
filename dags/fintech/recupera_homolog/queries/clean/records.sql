SELECT
    id_creditor,
    id_customer,
    customer_name,
    customer_document,
    brazilian_identity_card,
    brazilian_identity_card_issuing_federal_unit,
    spouse_name,
    CASE
        WHEN gender = "M" THEN "Masculino"
        WHEN gender = "F" THEN "Feminino"
        ELSE gender
    END AS gender,
    CASE
        WHEN marital_status = "S" THEN "Solteiro"
        WHEN marital_status = "C" THEN "Casado"
        WHEN marital_status = "D" THEN "Divorciado"
        WHEN marital_status = "E" THEN "Desquitado"
        WHEN marital_status = "V" THEN "Viúvo"
        WHEN marital_status = "O" THEN "Outros"
        ELSE marital_status
    END AS marital_status,
    customer_profession_code,
    customer_email,
    CASE
        WHEN mailing_address_type = "R" THEN "Residencial"
        WHEN mailing_address_type = "C" THEN "Comercial"
        ELSE mailing_address_type
    END AS mailing_address_type,
    CASE
        WHEN address_change = "A" THEN "Ambos"
        WHEN address_change = "C" THEN "Comercial"
        WHEN address_change = "R" THEN "Residencial"
        WHEN NULLIF(address_change, "Nulo") IS NULL THEN "Nenhum"
        ELSE address_change
    END AS address_change,
    CASE
        WHEN type_boleto_delivery = "1000" THEN "Correio (10)"
        WHEN type_boleto_delivery = "0100" THEN "E-mail (01)"
        WHEN type_boleto_delivery = "0010" THEN "SMS"
        WHEN type_boleto_delivery = "0001" THEN "Telefone"
        WHEN type_boleto_delivery = "1100" THEN "Correio e email (11)"
        WHEN type_boleto_delivery = "1010" THEN "Correio e SMS"
        WHEN type_boleto_delivery = "1001" THEN "Correio e telefone"
        WHEN type_boleto_delivery = "1110" THEN "Correio, email e SMS"
        WHEN type_boleto_delivery = "1101" THEN "Correio, email e telefone"
        WHEN type_boleto_delivery = "1011" THEN "Correio, SMS e telefone"
        WHEN type_boleto_delivery = "1111" THEN "Correio, email, SMS e telefone"
        WHEN type_boleto_delivery = "0110" THEN "Email e SMS"
        WHEN type_boleto_delivery = "0101" THEN "Email e telefone"
        WHEN type_boleto_delivery = "0111" THEN "Email, SMS e telefone"
        WHEN type_boleto_delivery = "0011" THEN "SMS e telefone"
        ELSE type_boleto_delivery
    END AS type_boleto_delivery,
    guarantor_name,
    guarantor_address,
    guarantor_neighborhood,
    guarantor_city,
    guarantor_state,
    guarantor_zip_code,
    guarantor_observations,
    guarantor_address_number,
    guarantor_address_complement,
    membership_description,
    residential_address,
    residential_district,
    residential_city,
    residential_state,
    residential_zip_code,
    residential_address_number,
    residential_address_complement,
    company_name,
    company_sector,
    company_position,
    commercial_address,
    commercial_neighborhood,
    commercial_city,
    commercial_state,
    commercial_zip_code,
    commercial_address_number,
    commercial_address_complement,
    complementary_data,
    CAST(income_amount AS FLOAT) AS income_amount,
    CAST(operations_amount AS INT) AS operations_amount,
    CAST(operations_number AS INT) AS operations_number,
    DATE(dt_customer_birth) AS dt_customer_birth,
    DATE(dt_customer_registration) AS dt_customer_registration,
    DATE(dt_admission) AS dt_admission,
    ts_load
FROM
    datalake_recupera_homolog_raw.records
