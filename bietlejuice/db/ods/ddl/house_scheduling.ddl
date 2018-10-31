drop table if exists property_scheduling;
create table property_scheduling (
  id_property_scheduling bigint,
  id_imovel integer not null,
  id_scheduling integer,
  id_owner integer,
  id_user_affiliate integer,
  id_user_agent integer,
  id_user_visitor integer,
  id_user_visit_agent integer,
  id_visit integer,
  visit_created_from_app integer,
  visit_created_type varchar(14),
  visit_last_updated_from_app integer,
  visit_last_updated_type varchar(14),
  id_rental_flow integer,
  id_negotiation integer,
  dt_negotiation timestamp,
  id_offer integer,
  id_pre_proposal integer,
  id_proposal integer,
  id_contract integer,
  dt_contract_anullment date
)
;