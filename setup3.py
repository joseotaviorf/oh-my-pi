from setuptools import setup, find_packages

__package_name__ = "bi-etl-ejuice"
__version__ = "0.1.0"
__repository_url__ = "https://github.com/quintoandar/bi-etl-ejuice"

with open('requirements3.txt') as f:
    all_requirements = [line for line in f.read().splitlines() if len(line) > 0]

external_requirements = []
for library in all_requirements:
    if not library.startswith('quintoandar'):
        external_requirements.append(library)

setup(
    name=__package_name__,
    version=__version__,
    url=__repository_url__,
    author='Data Engineering Team',
    packages=find_packages(exclude=["tests", "tests.*", "tests3", "tests3.*"]),
    include_package_data=True,
    install_requires=external_requirements,
    description='ETL jobs',
    dependency_links=[
        'https://quintoandar.github.io/python-package-server/'
    ]
)
