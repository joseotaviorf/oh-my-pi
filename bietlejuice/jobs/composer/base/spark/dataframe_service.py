import re
from collections import OrderedDict

from pyspark.sql.types import StructType
from pyspark.sql.functions import col, year, month, dayofmonth, to_json

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.spark import BaseSparkContext

spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

logger = QuintoAndarLogger('DataFrameService')


class DataFrameService():

    @staticmethod
    @logger
    def make_schema_merging(table_name, db, file_format, path, partition_by_list, df):
        df_aux = spark.sql('select * from {}.{} limit 0'.format(db, table_name))
        current_schema = OrderedDict(field.simpleString().split(':') for field in df_aux.schema.fields)
        new_data_schema = OrderedDict(field.simpleString().split(':') for field in df.schema.fields)

        current_columns_names = [k for k in current_schema]
        new_data_columns_names = [k for k in new_data_schema]

        new_columns = [c for c in new_data_columns_names if c not in current_columns_names]
        if not new_columns:
            logger.info('m=make_schema_merging, the schema is compatible no need to recreate table')
            return None
        else:
            logger.info('m=make_schema_merging, the schema is incompatible, creating new columns: {}'
                        .format(str(new_columns)))
            columns_ddl = ', '.join(["`{}` {}".format(k, current_schema[k]) for k in current_columns_names] + [
                "`{}` {}".format(k, new_data_schema[k]) for k in new_columns])
            partitions_ddl = ', '.join(partition_by_list)
            ddl = "create table {}.{} ({}) using {} partitioned by ({}) location '{}'".format(db, table_name,
                                                                                              columns_ddl,
                                                                                              file_format,
                                                                                              partitions_ddl,
                                                                                              path)
            logger.info('m=make_schema_merging, the schema is incompatible, new table definition: \n{}'.format(ddl))
            spark.sql('drop table {}.{}'.format(db, table_name))
            spark.sql(ddl)
            spark.sql('msck repair table {}.{}'.format(db, table_name))

    @staticmethod
    def column_name_format(column_name):
        formatted_name = re.sub(r'\W', '', column_name.replace(' ', '_').replace('.', '_'))
        formatted_name = re.sub(r'^([A-Z])', r'_\g<1>', formatted_name)
        formatted_name = re.sub(r'(.)_([A-Z])', r'\g<1>__\g<2>', formatted_name)
        return formatted_name.lower()

    @staticmethod
    def df_columns_name_format(df):
        existing_names = df.schema.fieldNames()
        new_names = [DataFrameService.column_name_format(name) for name in existing_names]
        for existing_name, new_name in zip(existing_names, new_names):
            df = df.withColumnRenamed(existing_name, new_name)
        return df

    @staticmethod
    @logger
    def incremental_write(df, file_format, partition_by_list, db, table_name, path, schema_merging=False):
        write_df = df.write \
            .mode('overwrite') \
            .format(file_format) \
            .partitionBy(*partition_by_list)

        if table_name not in sqlContext.tableNames(dbName=db):
            logger.info('m=incremental_write, db={}, table_name={}, '
                        .format(db, table_name) + 'msg=table does not exist in db, creating new...')
            write_df.option('path', path) \
                .saveAsTable(db + '.' + table_name)
        else:
            if schema_merging:
                DataFrameService.make_schema_merging(table_name, db, file_format, path, partition_by_list, df)
            logger.info('m=incremental_write, db={}, table_name={}, '
                        .format(db, table_name) + 'insert overwrite on right partition')
            write_df.save(path)
            spark.sql('msck repair table {}.{}'.format(db, table_name))

        logger.info('m=incremental_write, write finished, new data in: s3 path={} partitions={}'
                    .format(path, str(partition_by_list)))

    @staticmethod
    def df_struct_type_to_json(df):
        for f in df.schema.fields:
            if isinstance(f.dataType, StructType):
                logger.info('m=df_struct_type_to_json, converting struct {} to json'.format(f.name))
                df = df.withColumn(f.name, to_json(df[f.name]))
        return df

    @staticmethod
    def explode_json_column(df, json_column, prefix='', format_column_names=False):
        df_json_column = sqlContext.read.json(df.rdd.map(lambda r: getattr(r, json_column)))
        json_column_names = df_json_column.schema.fieldNames()

        json_tuple_columns = ', '.join(["'{}'".format(x) for x in json_column_names])
        if format_column_names:
            json_column_names = [DataFrameService.column_name_format(name) for name in json_column_names]
        json_tuple_alias = ', '.join(["`{}{}`".format(prefix, x) for x in json_column_names])

        df.registerTempTable('tmp_df')
        query = 'select *, json_tuple({}, {}) as ({}) from tmp_df'.format(json_column,
                                                                          json_tuple_columns,
                                                                          json_tuple_alias)
        return spark.sql(query).drop(json_column)

    @staticmethod
    def df_create_year_month_day_columns(df, date_column_name):
        return df.withColumn('year', year(col(date_column_name))) \
                 .withColumn('month', month(col(date_column_name))) \
                 .withColumn('day', dayofmonth(col(date_column_name)))
