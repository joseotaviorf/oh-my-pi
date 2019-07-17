from setuptools import setup, find_packages

with open('requirements3.txt') as f:
    install_requires = [line for line in f.read().splitlines() if len(line) > 0]

exclude_libs = ['python-logger==0.1.3']

for library in exclude_libs:
    install_requires.remove(library)

__package_name__ = "bi-etl-ejuice"
__version__ = "0.1.0"
__repository_url__ = "https://github.com/quintoandar/bi-etl-ejuice"

setup(
    name=__package_name__,
    version=__version__,
    url=__repository_url__,
    author='Data Engineering Team',
    packages=find_packages(exclude=["tests", "tests.*"]),
    install_requires=install_requires,
    description='ETL jobs',
    dependency_links=[
        'https://quintoandar.github.io/python-package-server/'
    ]
)
