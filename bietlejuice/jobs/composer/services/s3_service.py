import re

from os import path, makedirs

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("S3Service")


class S3Service:
    def __init__(self, s3_resource):
        """
        Handle the execution of common tasks on S3.
        :param s3_resource: boto3 s3 resource. It can be got with boto3.resource('s3')
        """
        self.s3_resource = s3_resource

    @staticmethod
    def _split_s3_path(s3_path):
        if not isinstance(s3_path, str) or not re.match("s3://.+/.*", s3_path):
            raise ValueError(
                "m=_split_s3_path, s3_path={}, msg=given s3_path is not a valid s3 path".format(
                    s3_path
                )
            )
        split = s3_path.split("/")
        bucket_name = split[2]
        suffix = "/".join(split[3:])
        return bucket_name, suffix

    @logger
    def upload_file(self, file_content, s3_file_path):
        """
        Upload a file to s3 giving raw file string and a full s3 path
        :param file_content: raw file content string
        :param s3_file_path: full path to the target s3 location, ex: "s3://bucket-name/path/to/file.txt"
        :return: None
        """
        bucket_name, key = self._split_s3_path(s3_file_path)
        self.s3_resource.Bucket(bucket_name).put_object(
            Key=key, Body=file_content.encode()
        )

    @logger
    def list_objects(self, s3_folder_path, include_size=False):
        """
        Recursively list all objects under a folder path in s3
        :param s3_folder_path: full path to the target folder in s3, ex: "s3://bucket-name/path/to/folder/"
        :param include_size: boolean parameter to include size of the objects alongside with the paths
        :return: list of all the objects discovered under the folder
        """
        bucket_name, objects_filter = self._split_s3_path(s3_folder_path)
        path_prefix = "s3://{}/".format(bucket_name)
        if include_size:
            return [
                (path_prefix + obj.key, obj.size)
                for obj in self.s3_resource.Bucket(bucket_name).objects.filter(
                    Prefix=objects_filter + "/"
                )
            ]
        return [
            path_prefix + obj.key
            for obj in self.s3_resource.Bucket(bucket_name).objects.filter(
                Prefix=objects_filter + "/"
            )
        ]

    @logger
    def download_file(self, s3_file_path, folder_destination):
        """
        Donwload a file from s3 to a specific location.

        :param s3_file_path: full path to the target s3 location, ex: "s3://bucket-name/path/to/file.txt"
        :param folder_destination: path to the target folder where the s3 file will be saved"
        :return: None
        """
        if not path.exists(folder_destination):
            makedirs(folder_destination)

        bucket_name, key = self._split_s3_path(s3_file_path)
        filename = key.split("/")[-1]
        self.s3_resource.Bucket(bucket_name).download_file(
            key, f"{folder_destination}/{filename}"
        )

    @logger
    def read_file(self, s3_file_path):
        """
        Read a file from s3 and return the file content.

        :param s3_file_path: full path to the target s3 location, ex: "s3://bucket-name/path/to/file.txt"
        :return: query string
        """
        bucket_name, key = self._split_s3_path(s3_file_path)
        return (
            self.s3_resource.Bucket(bucket_name)
            .Object(key)
            .get()["Body"]
            .read()
            .decode("utf-8")
        )

    @logger
    def list_sql_files(self, s3_file_path):
        """
        List all sql files from a given s3 path

        :param s3_file_path: full path to the target s3 location, ex: "s3://bucket-name/path/to/file.txt"
        :return: list of sql files
        """
        return list(
            filter(lambda x: x.endswith(".sql"), self.list_objects(s3_file_path))
        )

    @logger
    def delete_object(self, s3_object_path):
        """
        Delete a specific object from s3.
        :param s3_object_path: full path to the target s3 location, ex: "s3://bucket-name/path/to/object"
        :return: None
        """
        bucket_name, key = self._split_s3_path(s3_object_path)
        self.s3_resource.Object(bucket_name, key).delete()

    @logger
    def create_empty_object(self, s3_object_path):
        """
        Create a empty object in an s3 bucket.
        :param s3_object_path: full path to the target s3 location, ex: "s3://bucket-name/path/to/object"
        :return: None
        """
        bucket_name, key = self._split_s3_path(s3_object_path)
        self.s3_resource.Bucket(bucket_name).put_object(Key=key)
