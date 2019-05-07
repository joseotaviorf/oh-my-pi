drop table if exists inspection_item;
create table if not exists inspection_item (
  id bigint not null,
  "comment" text,
  photo_name varchar(255),
  id_room varchar(255),
  room_name varchar(255),
  id_inspection bigint,
  name varchar(255),
  id_reference varchar(255),
  "type" varchar(255),
  has_photo integer,
  ts_updated timestamp,
  ts_created timestamp,
  position integer,
  finishing varchar(255),
  operation varchar(255),
  tenant_comment text,
  owner_comment text
);