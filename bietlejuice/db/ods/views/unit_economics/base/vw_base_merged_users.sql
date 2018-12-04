drop table if exists unit_economics.vw_base_merged_users;
create table unit_economics.vw_base_merged_users as
with comma as (
  select
    unnest(string_to_array(email, ',')) as email,
    telefone,
    nome,
    tipo,
    contrato_id
  from contract_person
),
semi_colon as (
  select
    unnest(string_to_array(email, ',')) as email,
    telefone,
    nome,
    tipo,
    contrato_id
  from contract_person
),
contrato_pessoa as (
  select email, telefone, nome, tipo, contrato_id
  from comma
    union all
  select email, telefone, nome, tipo, contrato_id
  from semi_colon
),
users_prev as (
  select distinct
    coalesce(uc.email, up.email, cp.email, pp.email) as email,
    coalesce(uc.telefone_principal, up.telefone_principal) as main_phone,
    null as secondary_phone,
    null as commercial_phone,
    cp.telefone as contract_phone,
    pp.telefone as proposal_phone,
    ec.imovel_id as contract_property_id,
    null as proposal_property_id
  from contrato_pessoa cp
  left join contract ec
      on cp.contrato_id = ec.id
         and ec.status in ('Finalizado', 'Ativo')
  full outer join proponent_proposal pp
    on pp.email = cp.email
  full outer join usuario up
    on up.email = pp.email
  full outer join usuario uc
    on uc.email = cp.email
  left join proposal ep
    on ep.id = pp.proposta_id
),
booking_aux as (
    select
        eu.email,
        eu.telefone_principal,
        null::varchar as telefonesecundario,
        null::varchar as telefonecomercial,
        eb.imovel_id
    from booking eb
    join usuario eu
      on eb.visitante_id = eu.id
),
all_user as (
    select
        coalesce(up.email, h_ep.email_contato, b.email) as email,
        coalesce(up.main_phone, b.telefone_principal) as main_phone,
        coalesce(up.secondary_phone, b.telefonesecundario) as secondary_phone,
        coalesce(up.commercial_phone, b.telefonecomercial) as commercial_phone,
        up.contract_phone,
        up.proposal_phone,
        up.contract_property_id,
        up.proposal_property_id,
        h_ep.id as user_property_id,
        b.imovel_id as booking_property_id
    from users_prev up
    full outer join house h_ep
      on up.email = h_ep.email_contato
    full outer join booking_aux b
      on b.email = up.email
),
cols_to_rows as (
    select
        email,
        unnest(array[main_phone, secondary_phone, commercial_phone, contract_phone, proposal_phone]) as phone,
        unnest(array[contract_property_id, proposal_property_id::integer, user_property_id, booking_property_id]) as property_id
    from all_user
)
select distinct
    email,
    regexp_replace(coalesce(phone, max(phone) over (partition by email)), '^\+\d{2}|\D', '', 'g') as phone,
    property_id % 892700000 as property_id
from cols_to_rows
where (email is not null or phone is not null)
and property_id is not null
;