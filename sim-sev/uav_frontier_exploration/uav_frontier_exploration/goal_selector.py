# Goal Selector turns the top ranked frontier into a ROS goal message

from geometry_msgs.msg import PoseStamped
from typing import Optional, List
from .frontier import ScoredFrontier

class GoalSelector:
	def select(self, scored_frontiers: List[ScoredFrontier]) -> Optional[PoseStamped]:
		if not scored_frontiers:
			return None
		best = scored_frontiers[0].frontier
		goal = PoseStamped()
		goal.header.frame_id = "odom"
		goal.pose.position.x = float(best.position[0])
		goal.pose.position.y = float(best.position[1])
		goal.pose.position.z = 1.5
		goal.pose.orientation.w = 1.0
		return goal
	
