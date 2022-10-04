import argparse
import json
from typing import Tuple, List, Dict
from datetime import datetime

class SkipListFileUpdater:

    '''
    This class aims to manipulate text files, using the path of the files that will be used.
    Params:
        skip_list_path: path of the file containing the current skip_list to update it;
        dag_list_path: path of the file that contains the name of the dags you want to update.
        last_updater: Name of person who is using this script
    '''

    def __init__(self, skip_list_path: str, dag_list_path: str, last_updater: str) -> None:
        self.skip_list_path = skip_list_path
        self.dag_list_path = dag_list_path
        self.skip_list, self.dag_list = self.read_files()
        self.last_updater = last_updater

    def read_files(self) -> Tuple[Dict[str, str], List[str]]:
        
        with open(self.skip_list_path) as skip_stream, open(self.dag_list_path) as dag_stream:
            skip_list = json.load(skip_stream)
            dag_list = dag_stream.readlines()
        
        return skip_list, dag_list

    def update_list(self, current_date: str) -> None:
        
        for dag in self.dag_list:
            self.skip_list["dags"][dag.strip()] = current_date

    def update_file(self) -> None:

        self.skip_list["last_updater"] = self.last_updater

        with open(self.skip_list_path, "w") as stream:
            json.dump(self.skip_list, stream, indent=4)

if __name__ == '__main__':
    '''
    Adding the necessary parameters
    params:
        skip_list_path (Obrigatory): path of the file containing the current skip_list to update it;
        dag_list_path (Obrigatory): path of the file that contains the name of the dags you want to update;
        last_updater (Obrigatory): Name of the person who is updating the skip_list;
        today (Optional): date you want to add in the new skip_list records.
    '''

    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument('--json','-j', required=True, help='Path to the skip_list json')
    arg_parser.add_argument('--dags','-d', required=True, help='Path to the list of dags separated by line breaks')
    arg_parser.add_argument('--last_updater','-l', action='store', required=True, help='Name of the person who is updating the file')
    arg_parser.add_argument('--today','-t', required=False, help='Today\' date in this format: yyyy-MM-dd')

    args = arg_parser.parse_args()
    today = args.today if args.today is not None else datetime.today().strftime('%Y-%m-%d')

    '''
    Execution of functions
    '''

    file = SkipListFileUpdater(args.json, args.dags, args.last_updater)
    file.update_list(today)
    file.update_file()

    print(f"Skip list updated succesfully on {args.json}.")
    print("Please, validate this JSON on https://jsonlint.com/")
