from jobs.base.base_etl import BaseETL, EnumDb
import sys
import os
from datetime import datetime


args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename().replace('fact_','')

if len(args) > 1:
    if args[1] == 'ODS':

        print("Start query: {}".format(datetime.now()))

        table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query="call ebdb.list_property_scheduling();")

        print("To ODS: {}".format(datetime.now()))

        table = BaseETL.decode_table(table, 'LATIN-1')

        BaseETL.bulk_insert(
            table=table,
            table_name=process_name,
            db_enum=EnumDb.BI_ODS,
            encoding='UTF8',
            append=False,
            commit=True,
            bucket_name='{}/raw/ebdb/{}'.format(bucket_datalake, process_name)
        )

    elif args[1] == 'DW':
        BaseETL.execute_command(
            command="""
                drop table if exists property_listing;
                select 
                    * 
                into 
                    property_listing 
                from 
                    vw_property_listing
                ;
                
                
                ALTER TABLE public.property_listing
                  ADD CONSTRAINT property_listing_pk 
                    PRIMARY KEY ("id", "version");
                    
                CREATE INDEX property_listing_idx_min_v ON public.property_listing
                  USING btree ("min_version_time");
                  
                CREATE INDEX property_listing_idx_max_v ON public.property_listing
                  USING btree ("max_version_time");
            """,
            db_enum=EnumDb.BI_ODS,
            commit=True
        )
        print("{} - property_listing table created!", BaseETL.now())

        BaseETL.move_table_to_dw(
            table_name='vw_fact_liquidity_property_scheduling',
            table_name_dest='fact_liquidity_property_scheduling',
            enum_db_source=EnumDb.BI_ODS,
            enum_db_dest=EnumDb.BI_DW,
            append=False,
            bucket_name='{}/clean/ebdb/{}'.format(bucket_datalake, process_name),
            process_name=process_name
        )
