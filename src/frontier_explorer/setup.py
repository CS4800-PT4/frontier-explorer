from setuptools import find_packages, setup

package_name = 'frontier_explorer'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        ('share/' + package_name + '/rviz', ['rviz/frontier.rviz']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='general_use_account',
    maintainer_email='howard.l.general@gmail.com',
    description='Frontier-based exploration for the PX4 + EGO-Planner drone',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
            "template_node = frontier_explorer.template_node:main",
            "explorer_node = frontier_explorer.explorer_node:main",
        ],
    },
)
