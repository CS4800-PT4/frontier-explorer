"""One command for the real drone: ZED, MAVROS, XRCE agent, EGO, bridge and explorer.

    ros2 launch frontier_explorer hardware.launch.py camera_model:=zed2i

Nothing from the sim runs here (no Gazebo, no PX4 SITL). Each piece can be turned off
(zed:=false, mavros:=false, ...) to start it by hand or to test the rest in the sim
(sim/hw_profile_test.sh does that).

The camera intrinsics come from ~/.ego_hw/zed_intrinsics.yaml, written by
hw/zed_intrinsics.sh, unless fx/fy/cx/cy are given here.
"""
import os

import yaml
from ament_index_python.packages import PackageNotFoundError, get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, ExecuteProcess, IncludeLaunchDescription, OpaqueFunction
from launch.launch_description_sources import (AnyLaunchDescriptionSource,
                                               PythonLaunchDescriptionSource)
from launch_ros.actions import Node

# EGO sizes its depth buffer for 640 x 480 and writes past it on bigger images
# (grid_map.cpp), so the ZED has to publish at VGA (672 x 376) or smaller.
EGO_MAX_PIXELS = 640 * 480

ARGS = {
    # what to start
    'zed': ('true', 'Start the ZED wrapper'),
    'mavros': ('true', 'Start MAVROS (state from PX4, vision pose to PX4)'),
    'xrce': ('true', 'Start the Micro XRCE-DDS agent (setpoints to PX4)'),
    'ego': ('true', 'Start EGO planner and its trajectory server'),
    'bridge': ('true', 'Start the px4_ego offboard bridge'),
    'explorer': ('true', 'Start the frontier explorer'),
    'vision': ('true', 'Forward ZED odometry to PX4 as the indoor position'),
    # links
    'fcu_url': ('/dev/ttyACM0:57600', 'MAVROS link to the flight controller (USB by default)'),
    'gcs_url': ('', 'Optional QGroundControl link, e.g. udp-b://@'),
    'xrce_args': ('serial --dev /dev/ttyTHS1 -b 921600',
                  'MicroXRCEAgent arguments (Jetson UART to TELEM2 by default)'),
    # camera
    'camera_model': ('', 'ZED model for the wrapper: zed, zedm, zed2 or zed2i'),
    'zed_override': ('', 'ZED params file (default: config/zed_override.yaml in this package)'),
    'depth_topic': ('/zed/zed_node/depth/depth_registered', 'Depth image EGO maps from'),
    'zed_odom': ('/zed/zed_node/odom', 'ZED odometry forwarded to PX4'),
    'intrinsics_file': ('~/.ego_hw/zed_intrinsics.yaml', 'Written by hw/zed_intrinsics.sh'),
    'fx': ('', 'Depth camera fx (overrides intrinsics_file)'),
    'fy': ('', 'Depth camera fy'),
    'cx': ('', 'Depth camera cx'),
    'cy': ('', 'Depth camera cy'),
    'cam_x': ('0.0', 'Camera position from the flight controller, forward (m)'),
    'cam_y': ('0.0', 'Camera position, left (m)'),
    'cam_z': ('0.0', 'Camera position, up (m)'),
    'cam_pitch_deg': ('0.0', 'Camera tilt, positive = looking down (deg)'),
    # planner
    'odom_topic': ('/mavros/local_position/odom', 'Drone pose EGO and the explorer use'),
    'map_size_x': ('40.0', 'EGO and explorer map size (m)'),
    'map_size_y': ('40.0', 'Map size y (m)'),
    'map_size_z': ('4.0', 'EGO map height (m)'),
    'max_vel': ('0.5', 'EGO max speed (m/s); the sim uses 0.8'),
    'max_acc': ('0.8', 'EGO max acceleration (m/s^2); the sim uses 1.0'),
    'inflation': ('0.4', 'EGO obstacle padding (m), EGO_INFLATION in the sim'),
    'ground': ('0.3', 'EGO keeps the drone above this (m), EGO_GROUND'),
    'ceil': ('1.6', 'EGO virtual ceiling (m), EGO_CEIL'),
    'depth_timeout': ('1.0', 'EGO stops after this long without depth/odom (s)'),
}


def number(context, name):
    value = context.launch_configurations[name]
    try:
        return float(value)
    except ValueError:
        raise RuntimeError(f'{name}:={value!r} is not a number')


def is_on(context, name):
    return context.launch_configurations[name].lower() in ('true', '1', 'yes')


def intrinsics(context):
    """fx, fy, cx, cy from the launch arguments, else from the intrinsics file."""
    cfg = context.launch_configurations
    given = {k: cfg[k] for k in ('fx', 'fy', 'cx', 'cy') if cfg[k]}
    if len(given) == 4:
        return {k: float(v) for k, v in given.items()}
    if given:
        raise RuntimeError('give all of fx, fy, cx, cy or none of them')
    path = os.path.expanduser(cfg['intrinsics_file'])
    if not os.path.isfile(path):
        raise RuntimeError(f'no camera intrinsics: run bash hw/zed_intrinsics.sh first '
                           f'(writes {path}) or pass fx:= fy:= cx:= cy:=')
    with open(path) as f:
        data = yaml.safe_load(f) or {}
    missing = [k for k in ('fx', 'fy', 'cx', 'cy') if k not in data]
    if missing:
        raise RuntimeError(f'{path} is missing {missing}; run hw/zed_intrinsics.sh again')
    w, h = data.get('width', 0), data.get('height', 0)
    if w * h > EGO_MAX_PIXELS:
        raise RuntimeError(f'depth is {w}x{h}, EGO only handles up to 640x480 pixels '
                           f'(set the ZED to VGA and run hw/zed_intrinsics.sh again)')
    return {k: float(data[k]) for k in ('fx', 'fy', 'cx', 'cy')}


def share(package):
    try:
        return get_package_share_directory(package)
    except PackageNotFoundError:
        return None


def build(context):
    cfg = context.launch_configurations
    actions = []

    if is_on(context, 'zed'):
        if not cfg['camera_model']:
            raise RuntimeError('set camera_model:= (zed, zedm, zed2 or zed2i)')
        zed_share = share('zed_wrapper')
        if zed_share is None:
            raise RuntimeError('zed_wrapper is not installed: run hw/2_jetson_setup.sh and '
                               'source ~/zed_ws/install/setup.bash (or pass zed:=false)')
        override = cfg['zed_override'] or os.path.join(
            get_package_share_directory('frontier_explorer'), 'config', 'zed_override.yaml')
        actions.append(IncludeLaunchDescription(
            PythonLaunchDescriptionSource(os.path.join(zed_share, 'launch', 'zed_camera.launch.py')),
            launch_arguments={'camera_model': cfg['camera_model'],
                              'ros_params_override_path': override}.items()))

    if is_on(context, 'mavros'):
        mavros_share = share('mavros')
        if mavros_share is None:
            raise RuntimeError('mavros is not installed: source ~/mavros_ws/install/setup.bash')
        launch_args = {'fcu_url': cfg['fcu_url']}
        if cfg['gcs_url']:
            launch_args['gcs_url'] = cfg['gcs_url']
        actions.append(IncludeLaunchDescription(
            AnyLaunchDescriptionSource(os.path.join(mavros_share, 'launch', 'px4.launch')),
            launch_arguments=launch_args.items()))

    if is_on(context, 'xrce'):
        actions.append(ExecuteProcess(
            cmd=['MicroXRCEAgent'] + cfg['xrce_args'].split(), name='xrce_agent', output='screen'))

    if is_on(context, 'ego'):
        if share('ego_planner') is None:
            raise RuntimeError('ego_planner is not installed: source ~/ego_ws/install/setup.bash')
        cam = intrinsics(context)
        # advanced_param.launch.py reads these from the environment when it loads
        os.environ['EGO_INFLATION'] = str(number(context, 'inflation'))
        os.environ['EGO_GROUND'] = str(number(context, 'ground'))
        os.environ['EGO_CEIL'] = str(number(context, 'ceil'))
        os.environ['EGO_DEPTH_TIMEOUT'] = str(number(context, 'depth_timeout'))
        # Same as EGO's single_uav_gazebo.launch.py, plus the camera intrinsics
        ego_args = {
            'drone_id': '0',
            'map_size_x_': cfg['map_size_x'], 'map_size_y_': cfg['map_size_y'],
            'map_size_z_': cfg['map_size_z'],
            'odometry_topic': cfg['odom_topic'], 'depth_topic': cfg['depth_topic'],
            'cloud_topic': '/lidar_points',
            'fx': str(cam['fx']), 'fy': str(cam['fy']), 'cx': str(cam['cx']), 'cy': str(cam['cy']),
            'max_vel': cfg['max_vel'], 'max_acc': cfg['max_acc'],
            'planning_horizon': '7.5', 'use_distinctive_trajs': 'True', 'flight_type': '1',
            'point_num': '1', 'point0_x': '0.0', 'point0_y': '0.0', 'point0_z': '1.0',
        }
        actions.append(IncludeLaunchDescription(
            PythonLaunchDescriptionSource(os.path.join(
                get_package_share_directory('ego_planner'), 'launch', 'advanced_param.launch.py')),
            launch_arguments=ego_args.items()))
        actions.append(Node(
            package='ego_planner', executable='traj_server', name='drone_0_traj_server',
            output='screen',
            remappings=[('position_cmd', 'drone_0_planning/pos_cmd'),
                        ('planning/bspline', 'drone_0_planning/bspline')],
            parameters=[{'traj_server/time_forward': 1.0}]))
        actions.append(Node(
            package='tf2_ros', executable='static_transform_publisher', name='world_to_map',
            arguments=['0', '0', '0', '0', '0', '0', 'world', 'map']))
        actions.append(Node(
            package='tf2_ros', executable='static_transform_publisher', name='odom_to_base',
            arguments=['0', '0', '0', '0', '0', '0', 'odom', 'base_link']))
        actions.append(Node(
            package='frontier_explorer', executable='extrinsic_node', output='screen',
            parameters=[{'cam_x': number(context, 'cam_x'), 'cam_y': number(context, 'cam_y'),
                         'cam_z': number(context, 'cam_z'),
                         'cam_pitch_deg': number(context, 'cam_pitch_deg')}]))

    if is_on(context, 'bridge'):
        if share('px4_ego_py') is None:
            raise RuntimeError('px4_ego_py is not installed: source ~/px4_ego_ws/install/setup.bash')
        actions.append(Node(package='px4_ego_py', executable='offboard_control_test',
                            output='screen', additional_env={'PYTHONUNBUFFERED': '1'}))

    if is_on(context, 'explorer'):
        actions.append(Node(
            package='frontier_explorer', executable='explorer_node', output='screen',
            additional_env={'PYTHONUNBUFFERED': '1'},
            parameters=[{'depth_topic': cfg['depth_topic'], 'odom_topic': cfg['odom_topic'],
                         'map_size_x': number(context, 'map_size_x'),
                         'map_size_y': number(context, 'map_size_y')}]))

    if is_on(context, 'vision'):
        actions.append(Node(
            package='frontier_explorer', executable='vision_relay', output='screen',
            parameters=[{'odom_in': cfg['zed_odom']}]))

    return actions


def generate_launch_description():
    return LaunchDescription(
        [DeclareLaunchArgument(name, default_value=default, description=text)
         for name, (default, text) in ARGS.items()]
        + [OpaqueFunction(function=build)])
