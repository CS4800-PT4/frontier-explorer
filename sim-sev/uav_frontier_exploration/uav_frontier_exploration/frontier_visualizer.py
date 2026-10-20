# Publishes visualization markers so we can see the frontiers in RViz

from visualization_msgs.msg import MarkerArray, Marker
from std_msgs.msg import ColorRGBA


class FrontierVisualizer:
    def __init__(self, node):
        self.node = node
        self.pub = node.create_publisher(MarkerArray, '/frontier_markers', 10)

    def publish_markers(self, frontiers, selected=None):
        marker_array = MarkerArray()
        # TODO: create one Marker (sphere) per frontier
        # use different color for the selected one
        self.pub.publish(marker_array)