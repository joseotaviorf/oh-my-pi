drop table if exists zendesk.chats;
CREATE TABLE zendesk.chats (
	id varchar(25),
	zendesk_ticket_id int4,
	chat_start_timestamp timestamp,
	chat_end_timestamp timestamp,
	missed bool,
	unread bool,
	"comment" varchar(255),
	department_name varchar(255),
	started_by varchar(30),
	rating varchar(10),
	email varchar(255),
	extracted_date date,
	first_visitor_msg timestamp,
	first_answer timestamp,
	last_answer timestamp,
	last_visitor_msg timestamp,
	avg_response_time float8
) ;
