insert into {ods_table_name}
    select *
    from f_list_imovel_status_full_history({offset},{offset_increment})
    where all_status_date_position_flag
;