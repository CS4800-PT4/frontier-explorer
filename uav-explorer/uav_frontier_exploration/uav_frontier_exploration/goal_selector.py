# Goal Selector turns the top ranked frontier into a PoseStamped goal for EGO

from geometry_msgs.msg import PoseStamped
from typing import Optional, List
from .frontier import ScoredFrontier

class GoalSelector:
	def __init__(self, frame_id: str = "map", goal_z: float = 1.0):
		self.frame_id = frame_id	# EGO's goal frame
		self.goal_z = goal_z		# flight height (m)


	def select(self, scored_frontiers: List[ScoredFrontier]) -> Optional[PoseStamped]:
		if not scored_frontiers:
			return None
		# Lowest cost is first after rank()
		best = scored_frontiers[0].frontier
		goal = PoseStamped()
		goal.header.frame_id = self.frame_id
		goal.pose.position.x = float(best.position[0])
		goal.pose.position.y = float(best.position[1])
		goal.pose.position.z = float(self.goal_z)
		goal.pose.orientation.w = 1.0	# no rotation, EGO picks its own heading
		return goal
	
