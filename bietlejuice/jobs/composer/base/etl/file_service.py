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
