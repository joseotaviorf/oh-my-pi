# TODO Create table from dictionary or array.
import re
import sys

import boto3
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import pyathenajdbc

reload(sys)
sys.setdefaultencoding('utf8')

from jobs.base.base_etl import BaseETL


class AthenaWrapper(BaseETL):
    def __init__(self, staging_dir, *args, **kwargs):
        super(AthenaWrapper, self).__init__(*args, **kwargs)
        self.staging_dir = staging_dir

    def execute_query(self, sql):
        s3_staging_dir = 's3://{}/query_results/'.format(self.staging_dir)
        conn = pyathenajdbc.connect(s3_staging_dir=s3_staging_dir, region_name='us-east-1')

        with conn.cursor() as cursor:
            cursor.execute(sql)
            try:
                return pyathenajdbc.util.as_pandas(cursor)
            except ValueError:
                return None

    def create_parquet(self, key, query, raw_columns, clean_columns=None):
        print("Querying on Athena...")
        print(query)
        data = self.execute_query(query)
        data = data.astype(object).where(pd.notnull(data), None)

        new_data = pd.DataFrame()
        if raw_columns is not None:
            for index, col_key in enumerate(raw_columns):
                col, _type = col_key, raw_columns[col_key]
                for row in xrange(data[col].shape[0]):
                    data.loc[row, col] = _type(data.loc[row, col]) if data.loc[row, col] else None

                    if clean_columns:
                        list_clean_columns = clean_columns.keys()
                        new_value = data.loc[row, col]

                        if type(clean_columns[list_clean_columns[index]]) == list:
                            regex_from = clean_columns[list_clean_columns[index]][1]
                            regex_to = clean_columns[list_clean_columns[index]][2]
                            new_value = re.sub(regex_from, regex_to, _type(data.loc[row, col]))

                        new_data.loc[row, list_clean_columns[index]] = new_value if new_value else None

        print("Creating parquet file...")

        table = pa.Table.from_pandas(df=new_data if clean_columns else data)
        with pa.BufferOutputStream() as file_handler:
            pq.write_table(table, file_handler)

        print("Saving to s3...")
        s3_bucket = boto3.resource('s3').Bucket(self.staging_dir)
        s3_bucket.put_object(Key=key, Body=file_handler.get_result().to_pybytes())

        print("{} ready!".format(key))

    def create_athena_table_with_json_serde(self, database, table_name, schema, location, partitions=None,
                                            serde_options=None, drop_if_exists=True):
        self._create_athena_table(database=database, table_name=table_name, schema=schema, location=location,
                                  partitions=partitions, serde='org.openx.data.jsonserde.JsonSerDe',
                                  serde_options=serde_options, drop_if_exists=drop_if_exists)

    def __create_athena_table(self, database, table_name, schema, location, serde, partitions=None,
                              serde_options=None, drop_if_exists=True):
        if drop_if_exists:
            self.execute_query("""DROP TABLE IF EXISTS {}.{}""".format(database, table_name))

        query = """CREATE EXTERNAL TABLE IF NOT EXISTS {}.{} ({}) """.format(database, table_name, schema)

        if partitions is not None:
            query += """PARTITIONED BY ({}) """.format(partitions)

        query += """ROW FORMAT SERDE {} """.format(serde)

        if serde_options is not None:
            query += """WITH SERDEPROPERTIES ({}) """.format(serde_options)

        query += """LOCATION '{}'""".format(location)

        print("Trying to create {}.{}...".format(database, table_name))

        self.execute_query(query)

        print("Table created! If it has partitions and you need them right now, run msck_repair_table function.")

    def msck_repair_table(self, database, table_name):
        self.execute_query("""MSCK REPAIR TABLE {}.{}""".format(database, table_name))

    def update_partitions(self, table, location):
        # An alternative approach would be to simply use an
        # "msck repair table fastly" statement but this is very slow at Athena.
        # we will pay to list all S3 keys, so try to be efficient with the location choice
        #
        #
        # if not location.endswith('/'):
        #     location += '/'
        #
        # bucket_path = 's3://{}/'.format(self.amplitude_bucket)
        # prefix = location[len(bucket_path):]
        #
        # all_keys = boto3.resource('s3').Bucket(self.amplitude_bucket).objects.filter(Prefix=prefix)
        #
        # objects = set([k.key for k in all_keys if k.key.endswith('.gz')])
        #
        # partitions = set()
        # for o in objects:
        #     partitions.add(o[:len(o) - o[::-1].find('/')])
        #
        # for p in list(partitions):
        #     pp = re.split('/|=', p)
        #
        #     sql = """ALTER TABLE {} ADD IF NOT EXISTS""".format(table)
        #     sql += """PARTITION (app = {}, event_type = '{}', server_upload_date = date '{}')""". \
        #         format(pp[1], pp[3], pp[5])
        #     sql += """LOCATION '{}'""".format(bucket_path + p)
        #
        #     print ("Adding new partition at {}".format(bucket_path + p))
        #     self._execute_query(sql)

        # TODO Need to figure out how to implement this one to be generic at location and partitions!
        raise NotImplementedError
