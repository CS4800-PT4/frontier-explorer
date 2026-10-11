# Node Documentation

This documentation is to provide guidance on creating and interacting with a ROS2 node.

## Node Setup
###  Step 1:
Create a new python file under src/frontier-explorer/frontier_explorer.

###  Step 2:
Write code in the python file to create a ROS2 Node. Use the template from template_node.py as a starting point.

### Step 3:
After writing the code necessary for a ROS2 node, go to setup.py. Relative to the root of the repository, this is located in src/frontier-explorer/setup.py. In setup.py under console_scripts in entry_points, follow this format to create the node.

"{node_name} = {package_name}.{python_file_name}:main"

For example, if you want to name the node template_node  under the frontier_explorer package and the python file name is template_node.py, this is how it would appear.

```bash
entry_points={
    'console_scripts': [
        "template_node = frontier_explorer.template_node:main"
    ],
},
```

### Step 4:
Edit ~/.bashrc to include the setup script from this repository if this has not been done yet. If ~/.bashrc does not have "source ~/frontier-explorer/install/setup.bash", run these commands.

```bash
echo "source ~/frontier-explorer/install/setup.bash" >> ~/.bashrc
source ~/.bashrc
```

### Step 5:
Run the build command from the root of the repository to include the changes to the build.

```bash
# Must run this command from the root of the repository
colcon build
```

## Node Execution
### Step 1:
Run this command to execute your node.
```bash
# Follow this format
ros2 run {package_name} {node_name}

# Here is an example with template_node
ros2 run frontier_explorer template_node

```

### Step 2:
To stop the node, press ctrl + c.