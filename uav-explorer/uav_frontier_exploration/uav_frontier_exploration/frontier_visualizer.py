# Publishes visualization markers so we can see the frontiers in RViz

from visualization_msgs.msg import MarkerArray, Marker
from std_msgs.msg import ColorRGBA
from geometry_msgs.msg import Point

def color(r, g, b, a=1.0):
    return ColorRGBA(r=r, g=g, b=b, a=a)

class FrontierVisualizer:
    def __init__(self, node, frame_id: str = 'map', goal_z: float = 1.0):
        self.node = node
        self.frame_id = frame_id
        self.goal_z = goal_z
        # Same topic as the team's explorer, so RViz configs still work
        self.pub = node.create_publisher(MarkerArray, '/frontier/markers', 1)

    def publish_markers(self, frontiers, selected=None, view=None):
        stamp = self.node.get_clock().now().to_msg()
        out = MarkerArray()
        # Clear last cycle's markers first
        clear = Marker()
        clear.action = Marker.DELETEALL
        out.markers.append(clear)

        def marker(ns, mtype, scale, col):
            m = Marker()
            m.header.frame_id = self.frame_id
            m.header.stamp = stamp
            m.ns, m.id, m.type = ns, len(out.markers),mtype
            m.pose.orientation.w = 1.0
            m.scale.x = m.scale.y = m.scale.z = scale
            m.color = col
            out.markers.append(m)
            return m

        z = self.goal_z
        if frontiers and view is not None:
            # Orange cubes = frontier cells, blue spheres = each frontier's goal
            cells = marker('frontier_cells', Marker.CUBE_LIST, view.res, color(1.0, 0.55, 0.0))
            goals = marker('frontier_goals', Marker.SPHERE_LIST, 0.25, color(0.2, 0.4, 1.0))
            for f in frontiers:
                for r, c in f.cells:
                    x, y = view.cell_center(r, c)
                    cells.points.append(Point(x=x, y=y, z=0.05))
                goals.points.append(Point(x=float(f.position[0]), y=float(f.position[1]), z=z))

        if selected is not None and view is not None and view.pose is not None:
            # Big green sphere = chosen goal, green line from the drone to it 
            gx, gy = float(selected.position[0]), float(selected.position[1])
            m = marker('best_goal', Marker.SPHERE, 0.5, color(0.1, 0.8, 0.2))
            m.pose.position = Point(x=gx, y=gy, z=z)
            line = marker('best_goal', Marker.LINE_STRIP, 0.05, color(0.1, 0.8, 0.2))
            px, py, pz, _ = view.pose
            line.points = [Point(x=px, y=py, z=pz), Point(x=gx, y=gy, z=z)]

        if view is not None and view.pose is not None:
            # Text above the drone: area seen and frontier count
            px, py, pz, _ = view.pose
            text = marker('status', Marker.TEXT_VIEW_FACING, 0.35, color(0.1, 0.1, 0.1))
            text.pose.position = Point(x=px, y=py, z=pz + 0.8)
            text.text = f'{view.known_area():.0f} m2 seen, {len(frontiers)} frontiers'

        self.pub.publish(out)