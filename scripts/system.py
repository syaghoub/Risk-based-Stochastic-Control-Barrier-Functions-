from sympy import symbols, Matrix, sin, cos, lambdify, exp, sqrt, log, diff
from geometry_msgs.msg import PoseStamped
from geometry_msgs.msg import Vector3
from nav_msgs.msg import Odometry
from geometry_msgs.msg import Twist
import numpy as np
import rospy

# ROS others
import tf



class System(object):

    """ System class

    Args:
        object (system class): creates object of a system, and includes methods for modifying it

    Returns:
        system object: the model describes dx = f(x) + g(x)*inputs , y = Cx where x is the system states
    """
    ####TODO: check whether you need Matrix here or not

    def __init__(self, name, states, inputs, f, g = None, C = None, inputRange = None):
        # TODO: Check the observability given C, the assert part may need more attention too
        self.name = name
        self.states = states
        self.inputs = inputs
        self.inputRange = inputRange
        self.f = f
        self.state_traj = []
        self.control_traj = []
        self.currState = []
        self.nDim = len(states)
        self.full_observability = True  #! Changed the name of the attribute # If true the states are fully and precisely observable
        if g is not None:
            # self.g = Matrix(g) #! This should already be given as Matrix
            try:  #! Try catch should not be used for this. We can just check dimensions
                self.f+self.g*self.inputs
            except:
                raise ValueError("Inappropriate g or inputs sizes")
            self.dx = self.f+self.g*self.inputs
        else:
            self.dx = self.f
         # TODO: Check the observability given C, the assert part may need more attention too
        if C is not None:
            if np.array(C).shape != np.eye(self.nDim).shape or not p.allclose(np.eye(self.nDim),C):
                assert np.array(C).shape[1] == self.nDim, "inappropriate C shape"   #y = CX
                self.C = Matrix(C) #! This should be given as Matrix, no need to cast again
                self.full_observability = False

    def add_state_traj(self, state, time):
        self.currState = state
        self.state_traj.append([time, state[:]])

    def add_control_traj(self, control, time):
        self.control_traj.append([time, control[:]])

    def system_details(self):
        return '{}\n {}\n {}\n {}\n {}\n {}\n {}\n'.format(self.name, self.states, self.inputs, self.f, self.g, self.C, self.full_observability)

class Stochastic(System):
    def __init__(self, name, states, inputs, f, g = None, C = None, G = None, D= None): # G, and D
        super(Stochastic, self).__init__(name, states, inputs, f, g , C)
        nDim = len(self.states)
        if G is None and D is None:
            raise ValueError("Did you mean to create a deterministic system?")

        if G is not None:
            assert np.array(G).shape[0] == nDim, "inappropriate G shape"   #dx = f(x)+Gdw
            self.G = Matrix(G) #! This should be given as Matrix, no need to cast again
        else:
            self.G = G #! I don't understand this if-else
        if D is not None:
            if self.C is None:
                self.C = np.eye(nDim)
            assert np.array(D).shape[0] == self.model.C.shape[0]
            self.D = Matrix(D) #! This should be given as Matrix, no need to cast again
            self.full_observability = False



    def system_details(self):
        superOut = super(Stochastic, self).system_details()
        out = superOut + '{}\n {}\n'.format(self.D, self.G)
        return out






class Connected_system(object):
    def __init__(self,ego_system,CBFList):
        self.ego = ego_system
        self.CBFList = CBFList
        self.vw_publisher = rospy.Publisher('/hsrb/command_velocity', Twist, queue_size=10)


        # # subscliber to get odometry of HSR & agents
        rospy.Subscriber('/hsrb/odom_ground_truth', Odometry, self.tOdometry_callback, queue_size=10)
        # rospy.Subscriber('/global_pose', PoseStamped, odometry_callback, queue_size=10)

        # assume we have read the names of agents from ROS and stored them here
        self.i = 0
        for CBF in self.CBFList:
            agentname = CBF.agent.name
            rospy.Subscriber('/'+agentname+'pose', PoseStamped, self.agent_callback, callback_args = agentname, queue_size=10)

    def tOdometry_callback(self, odometry):
        now = rospy.get_rostime()
        time = now.secs+now.nsecs*pow(10,-9)
        p = odometry.pose.pose.position
        angular = orientation2angular(odometry.pose.pose.orientation)      # transfer orientaton(quaternion)->agular(euler)
        state = [p.x,p.y,angular.z]
        self.ego.add_state_traj(state, time)

    def odometry_callback(self, poseStamped):
        poseStamped = poseStamped

    def agent_callback(self, agentPose, agentname):
        now = rospy.get_rostime()
        time = now.secs+now.nsecs*pow(10,-9)
        p = agentPose.pose.position
        angular = orientation2angular(agentPose.pose.orientation)      # transfer orientaton(quaternion)->agular(euler)
        state = [p.x,p.y,angular.z]
        for i in range(len(self.CBFList)):
            if self.CBFList[i].agent.name == agentname:
                self.CBFList[i].agent.add_state_traj(state,time)

    def publish(self, u):
        now = rospy.get_rostime()
        time = now.secs+now.nsecs*pow(10,-9)
        vel_msg = Twist()
        vel_msg.linear.x  = u[0]
        vel_msg.angular.z = u[1]
        self.ego.add_control_traj(u,time)
        self.vw_publisher.publish(vel_msg)



def orientation2angular(orientation):
    quaternion = (  orientation.x,
                    orientation.y,
                    orientation.z,
                    orientation.w)
    euler = tf.transformations.euler_from_quaternion(quaternion)
    angular = Vector3(
            euler[0],
            euler[1],
            euler[2]
    )
    return angular
