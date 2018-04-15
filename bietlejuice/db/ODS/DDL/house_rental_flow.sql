drop table if exists house_rental_flow;
create table house_rental_flow (
  id_house_rental_flow bigint,
  id_house integer not null,
  id_rental_flow integer,
  id_owner integer,
  id_client integer,
  id_booking integer,
  id_user_agent integer,
  id_user_visit_agent integer,
  id_visit integer,
  visit_created_from_app integer,
  visit_created_type varchar(14),
  visit_last_updated_from_app integer,
  visit_last_updated_type varchar(14),
  id_negotiation integer,
  id_offer integer,
  id_pre_proposal integer,
  id_proposal integer,
  id_contract integer
)
;