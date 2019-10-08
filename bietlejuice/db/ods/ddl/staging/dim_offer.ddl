drop table if exists staging.dim_offer;
create table staging.dim_offer (
  sk_offer integer,
  id_offer integer,
  id_godfather integer,
  id_firestore varchar(255),
  last_offered_rent integer,
  original_rent integer,
  original_condo integer,
  dt_approved timestamp,
  editing varchar(255),
  status varchar(255),
  id_user integer,
  id_property integer,
  dt_created timestamp,
  dt_updated timestamp,
  dt_timestamp timestamp without time zone,
  offer_submitted boolean,
  dt_first_sent timestamp,
  last_updated_date timestamp,
  expiration_date timestamp,
  last_rent_offered_by_tenant decimal(18,4),
  last_rent_offered_by_owner decimal(18,4),
  rejection_reason varchar(255),
  type varchar(255)
)
;