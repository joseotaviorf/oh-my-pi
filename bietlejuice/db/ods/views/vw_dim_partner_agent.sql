--drop view if exists vw_dim_partner_agent;
--create or replace view vw_dim_partner_agent as
SELECT
    id as sk_partner_agent,
    id as id_partner_agent,
    status as status_partner_agent, -- activate or deactivate relationship Partner <> User 
    user_id as id_user,
    partner_id as id_partner,
    type,
    ts_updated, 
    ts_created,
    now()::timestamp as ts_load
FROM
partner_agent;
