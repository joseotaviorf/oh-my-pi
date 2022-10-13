DROP TABLE IF EXISTS public.dim_agent;
CREATE TABLE public.dim_agent (
    sk_agent INTEGER PRIMARY KEY,
    id_user BIGINT,
    name VARCHAR(255),
    cpf VARCHAR(255)
    rg VARCHAR(30)
    sex VARCHAR(255),
    email VARCHAR(255),
    alternative_email VARCHAR(255),
    main_phone_number VARCHAR(255),
    address VARCHAR(255),
    number VARCHAR(255),
    complement VARCHAR(255),
    neighborhood VARCHAR(255),
    cep VARCHAR(255),
    city VARCHAR(255),
    state_name VARCHAR(200),
    state_abbreviation VARCHAR(200),
    country_code VARCHAR(255),
    work_contract_name VARCHAR(255),
    rede_partner VARCHAR(255),
    agent_type VARCHAR(255),
    agent_profile VARCHAR(255),
    agent_creci VARCHAR(255),
    is_user_active BOOLEAN,
    is_blocked BOOLEAN,
    is_affiliate_active BOOLEAN,
    is_agent_active BOOLEAN,
    is_photographer_active BOOLEAN,
    is_tenant BOOLEAN,
    is_sale_agent BOOLEAN,
    is_rent_agent BOOLEAN,
    is_rede_agent BOOLEAN,
    dt_birth DATE,
    ts_created TIMESTAMP,
    ts_updated TIMESTAMP,
    ts_load TIMESTAMP
);

ALTER TABLE public.dim_agent OWNER TO databricks;