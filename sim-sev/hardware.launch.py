"""SEV hardware launch (sim-sev only). Real drone: ZED + MAVROS + XRCE + EGO + bridge.

No Gazebo. No PX4 SITL. Lives under sim-sev/ so team src/hw/sim stay untouched.

    ros2 launch ~/frontier-explorer/sim-sev/hardware.launch.py

Defaults match our Jetson bring-up + live-demo:
  camera_model:=zed2i
  explorer:=false   (start explorer later via live-demo/run_demo.sh)
  fcu_url:=/dev/ttyACM0:57600   (FC USB → MAVROS)
  xrce on /dev/ttyTHS1 @ 921600 (Jetson UART → TELEM2)

Override anything the same way as usual, e.g.:
  ros2 launch ~/frontier-explorer/sim-sev/hardware.launch.py fcu_url:=/dev/ttyUSB0:921600
"""
import math
import os

import yaml
from ament_index_python.packages import PackageNotFoundError, get_package_share_directory
from launch import LaunchDescription
from launch.actions import (DeclareLaunchArgument, ExecuteProcess, IncludeLaunchDescription,
                            LogInfo, OpaqueFunction)
from launch.launch_description_sources import (AnyLaunchDescriptionSource,
                                               PythonLaunchDescriptionSource)
from launch_ros.actions import Node

# Directory of this file (sim-sev/), so config/ stays next to us.
_SIM_SEV = os.path.dirname(os.path.abspath(__file__))

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
    # live-demo starts explorer_node after takeoff/hover — leave off by default
    'explorer': ('false', 'Start the frontier explorer (false for manual live-demo)'),
    'vision': ('true', 'Forward ZED odometry to PX4 as the indoor position'),
    # links — Jetson Orin Nano + PX4 USB + TELEM2 UART
    'fcu_url': ('/dev/ttyACM0:57600', 'MAVROS link to the flight controller (USB by default)'),
    'gcs_url': ('', 'Optional QGroundControl link, e.g. udp-b://@'),
    'xrce_args': ('serial --dev /dev/ttyTHS1 -b 921600',
                  'MicroXRCEAgent arguments (Jetson UART to TELEM2 by default)'),
    # camera — ZED 2i on our airframe
    'camera_model': ('zed2i', 'ZED model for the wrapper: zed, zedm, zed2 or zed2i'),
    'zed_override': ('', 'ZED params file (default: sim-sev/config/zed_override.yaml)'),
    'depth_topic': ('/zed/zed_node/depth/depth_registered', 'Depth image EGO maps from'),
    'zed_odom': ('/zed/zed_node/odom', 'ZED odometry forwarded to PX4'),
    'zed_status': ('/zed/zed_node/pose/status', 'ZED tracking status; poses are held back '
                   'while it is not OK (empty = do not check)'),
    'intrinsics_file': ('~/.ego_hw/zed_intrinsics.yaml', 'Written by hw/zed_intrinsics.sh'),
    'fx': ('', 'Depth camera fx (overrides intrinsics_file)'),
    'fy': ('', 'Depth camera fy'),
    'cx': ('', 'Depth camera cx'),
    'cy': ('', 'Depth camera cy'),
    'cam_x': ('0.0', 'Camera position from the flight controller, forward (m)'),
    'cam_y': ('0.0', 'Camera position, left (m)'),
    'cam_z': ('0.0', 'Camera position, up (m)'),
    'cam_pitch_deg': ('0.0', 'Camera tilt, positive = looking down (deg). Only EGO uses it; '
                      'the explorer and vision_relay assume a level camera'),
    # planner
    'odom_topic': ('/mavros/local_position/odom', 'Drone pose EGO and the explorer use'),
    'map_size_x': ('40.0', 'EGO and explorer map size (m)'),
    'map_size_y': ('40.0', 'Map size y (m)'),
    'map_size_z': ('4.0', 'EGO map height (m)'),
    'max_vel': ('0.3', 'EGO max speed (m/s); class demo keeps this slow'),
    'max_acc': ('0.5', 'EGO max acceleration (m/s^2); class demo keeps this gentle'),
    'inflation': ('0.4', 'EGO obstacle padding (m), EGO_INFLATION in the sim'),
    'ground': ('0.3', 'EGO keeps the drone above this (m), EGO_GROUND'),
    'ceil': ('2.2', 'EGO virtual ceiling (m); above ~2 m takeoff hold'),
    'depth_timeout': ('1.0', 'EGO stops after this long without depth/odom (s)'),
}


def number(context, name):
    value = context.launch_configurations[name]
    try:
        return float(value)
    except ValueError:
        raise RuntimeError(f'{name}:={value!r} is not a number')


def double(context, name):
    """A number as EGO's launch wants it: '1' would reach EGO as an int and crash it."""
    return str(number(context, name))


def is_on(context, name):
    return context.launch_configurations[name].lower() in ('true', '1', 'yes')


def intrinsics(context):
    """fx, fy, cx, cy (and width when known) from the launch arguments, else the file."""
    cfg = context.launch_configurations
    given = {k: cfg[k] for k in ('fx', 'fy', 'cx', 'cy') if cfg[k]}
    if len(given) == 4:
        return {k: number(context, k) for k in given}
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
    cam = {k: float(data[k]) for k in ('fx', 'fy', 'cx', 'cy')}
    if w:
        cam['width'] = w
    return cam


def fov_deg(cam):
    """Horizontal field of view of the depth image, for the explorer's sweep."""
    return math.degrees(2.0 * math.atan(cam['width'] / 2.0 / cam['fx']))


def share(package):
    try:
        return get_package_share_directory(package)
    except PackageNotFoundError:
        return None


def zed_override_path(cfg):
    if cfg['zed_override']:
        return cfg['zed_override']
    local = os.path.join(_SIM_SEV, 'config', 'zed_override.yaml')
    if os.path.isfile(local):
        return local
    # Fallback only if someone deleted our copy — still do not edit team files
    fe = share('frontier_explorer')
    if fe:
        return os.path.join(fe, 'config', 'zed_override.yaml')
    raise RuntimeError('missing sim-sev/config/zed_override.yaml')


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
        override = zed_override_path(cfg)
        actions.append(IncludeLaunchDescription(
            PythonLaunchDescriptionSource(os.path.join(zed_share, 'launch', 'zed_camera.launch.py')),
            launch_arguments={'camera_model': cfg['camera_model'],
                              'ros_params_override_path': override}.items()))

    if is_on(context, 'mavros'):
        mavros_share = share('mavros')
        if mavros_share is None:
            raise RuntimeError('mavros is not installed: run sudo bash hw/1_jetson_sudo.sh '
                               '(the sim builds it in ~/mavros_ws)')
        launch_args = {'fcu_url': cfg['fcu_url']}
        if cfg['gcs_url']:
            launch_args['gcs_url'] = cfg['gcs_url']
        actions.append(IncludeLaunchDescription(
            AnyLaunchDescriptionSource(os.path.join(mavros_share, 'launch', 'px4.launch')),
            launch_arguments=launch_args.items()))

    if is_on(context, 'xrce'):
        actions.append(ExecuteProcess(
            cmd=['MicroXRCEAgent'] + cfg['xrce_args'].split(), name='xrce_agent', output='screen'))

    cam = intrinsics(context) if is_on(context, 'ego') else {}

    if is_on(context, 'ego'):
        if share('ego_planner') is None:
            raise RuntimeError('ego_planner is not installed: source ~/ego_ws/install/setup.bash')
        os.environ['EGO_INFLATION'] = str(number(context, 'inflation'))
        os.environ['EGO_GROUND'] = str(number(context, 'ground'))
        os.environ['EGO_CEIL'] = str(number(context, 'ceil'))
        os.environ['EGO_DEPTH_TIMEOUT'] = str(number(context, 'depth_timeout'))
        ego_args = {
            'drone_id': '0',
            'map_size_x_': double(context, 'map_size_x'),
            'map_size_y_': double(context, 'map_size_y'),
            'map_size_z_': double(context, 'map_size_z'),
            'odometry_topic': cfg['odom_topic'], 'depth_topic': cfg['depth_topic'],
            'cloud_topic': '/lidar_points',
            'fx': str(cam['fx']), 'fy': str(cam['fy']), 'cx': str(cam['cx']), 'cy': str(cam['cy']),
            'max_vel': double(context, 'max_vel'), 'max_acc': double(context, 'max_acc'),
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
        # extrinsic_node / vision_relay / explorer_node come from installed frontier_explorer
        # package binaries — we launch them; we do not edit team source under src/.
        actions.append(Node(
            package='frontier_explorer', executable='extrinsic_node', output='screen',
            parameters=[{'cam_x': number(context, 'cam_x'), 'cam_y': number(context, 'cam_y'),
                         'cam_z': number(context, 'cam_z'),
                         'cam_pitch_deg': number(context, 'cam_pitch_deg')}]))

    if is_on(context, 'bridge'):
        if share('px4_ego_py') is None:
            raise RuntimeError('px4_ego_py is not installed: source ~/px4_ego_ws/install/setup.bash '
                               '(or ~/px4_ego/install/setup.bash)')
        actions.append(Node(package='px4_ego_py', executable='offboard_control_test',
                            output='screen', additional_env={'PYTHONUNBUFFERED': '1'}))

    if is_on(context, 'explorer'):
        params = {'depth_topic': cfg['depth_topic'], 'odom_topic': cfg['odom_topic'],
                  'map_size_x': number(context, 'map_size_x'),
                  'map_size_y': number(context, 'map_size_y')}
        if 'width' in cam:
            params['fov_deg'] = fov_deg(cam)
        if number(context, 'cam_pitch_deg') != 0.0:
            actions.append(LogInfo(msg='WARNING: cam_pitch_deg is not 0, but the explorer '
                                       'assumes a level camera when it marks space as seen'))
        actions.append(Node(
            package='frontier_explorer', executable='explorer_node', output='screen',
            additional_env={'PYTHONUNBUFFERED': '1'}, parameters=[params]))

    if is_on(context, 'vision'):
        actions.append(Node(
            package='frontier_explorer', executable='vision_relay', output='screen',
            parameters=[{'odom_in': cfg['zed_odom'], 'status_in': cfg['zed_status']}]))

    return actions


def generate_launch_description():
    return LaunchDescription(
        [DeclareLaunchArgument(name, default_value=default, description=text)
         for name, (default, text) in ARGS.items()]
        + [OpaqueFunction(function=build)])
