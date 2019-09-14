import os

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("FileService")


class FileService:
    @staticmethod
    @logger
    def get_query_from_file_name(file_name):
        try:
            with open(file_name) as f:
                return f.read()
        except IOError as ex:
            raise RuntimeError(
                "m=get_query_from_file_name, file_name={}, msg=file not found, ex={}".format(
                    file_name, ex
                )
            )

    def _full_path_builder(self, relative_path):
        return os.path.join(os.path.dirname(os.path.realpath(__file__)), relative_path)

    @logger(exclude_return=True)
    def get_destination_datalake_query(self, schema, stage, table):
        path = self._full_path_builder(
            "../../db/destination/datalake/{}/{}/{}.sql".format(schema, stage, table)
        )
        return self.get_query_from_file_name(path)

    @logger(exclude_return=True)
    def get_destination_dw_query(self, schema, table):
        path = self._full_path_builder(
            "../../db/destination/dw/{}/{}.sql".format(schema, table)
        )
        return self.get_query_from_file_name(path)
