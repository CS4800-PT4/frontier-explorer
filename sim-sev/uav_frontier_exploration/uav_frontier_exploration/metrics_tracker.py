# Metrics tracks areas explored distance and failed goals

class MetricsTracker:
	def __init__(self):
		self.explored_area = 0.0
		self.distance_traveled = 0.0
		self.failed_goals = 0
		
	def update(self, explored_area: float, distance_delta: float = 0.0):
		self.explored_area = explored_area
		self.distance_traveled += distance_delta
