from setuptools import find_packages, setup

package_name = 'frontier_explorer'

setup(
    name=package_name,
    version='0.2.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        ('share/' + package_name + '/rviz', ['rviz/frontier.rviz']),
        ('share/' + package_name + '/launch', ['launch/hardware.launch.py']),
        ('share/' + package_name + '/config', ['config/zed_override.yaml']),
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
            "extrinsic_node = frontier_explorer.extrinsic_node:main",
            "vision_relay = frontier_explorer.vision_relay:main",
        ],
    },
)
