import rclpy
from rclpy.node import Node

# You can execute this node as is to get an idea of how to run a ROS2 node. This can also be used
# as a starting point for creating nodes.

class TemplateNode(Node):
    def __init__(self):
        # initializes ROS2 node. Replace "template_node" with the desired node name
        super().__init__("template_node")

        # This is how to log node information to the terminal. Replace "Template node logging" with the information that you want to appear on the terminal
        self.get_logger().info("Template node logging")
        
        # Example of how to publish
        # self.publisher = self.create_publisher(TopicType, '/topic/path', 10)

        # Example of how to subscribe. Whenever data is received, the subscriber_function is ran
        # self.subscriber = self.create_subscription(TopicType, '/topic/path', self.subscriber_function, 10)

    # subscription_data is the data received from the topic
    # def subscriber_function(self, subscription_data):
    #     pass

def main(args=None):
    # Activates template_node
    rclpy.init(args=args)
    node = TemplateNode()
    rclpy.spin(node)

    # Shuts down node
    rclpy.shutdown()

if __name__ == "__main__":
    main()