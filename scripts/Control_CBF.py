# from HSR_control import get_model_srv
from gazebo_msgs.srv import GetWorldProperties, GetModelState, GetModelStateRequest
import numpy as np
import rospy
import matplotlib.pyplot as plt
import cvxopt as cvxopt

def cvxopt_solve_qp(P, q, G=None, h=None, A=None, b=None):
    P = .5 * (P + P.T)  # make sure P is symmetric
    args = [cvxopt.matrix(P), cvxopt.matrix(q)]
    if G is not None:
        args.extend([cvxopt.matrix(G), cvxopt.matrix(h)])
        if A is not None:
            args.extend([cvxopt.matrix(A), cvxopt.matrix(b)])
    cvxopt.solvers.options['show_progress'] = False
    cvxopt.solvers.options['maxiters'] = 100
    sol = cvxopt.solvers.qp(*args)
    if 'optimal' not in sol['status']:
        return None
    return np.array(sol['x']).reshape((P.shape[1],))

class Control_CBF(object):
        def __init__(self, connected_system, goal_func, MapInfo , IncludeRadius = 10):  # make sure ego is the system with which CBF is created 
                self.connected_system = connected_system
                self.GoalInfo = goal_func
                self.MapInfo = MapInfo
                self.IncludeRadius = IncludeRadius
                self.count = 0 # num of times control_callback is called


        def controller_callback(self, event):
                # this controller loop call back.
                self.count += 1


                #         # making vw data and publish it.
                #         vel_msg = Twist()
                #         # Compute controller
                #         if abs(p.x)<1.5 and self.flag == 0:
                #                 self.flag = 1
                #                 env_bounds = type('', (), {})()
                #                 env_bounds.x_max = 1.2
                #                 env_bounds.x_min = -1.3
                #                 self.MapInfo = self.robot.MapFuncs(env_bounds)
                #                 GoalCenter = np.array([0, 5.5])
                #                 self.GoalInfo = self.robot.GoalFuncs(GoalCenter,rGoal)

                u = self.cbf_controller_compute()

                self.connected_system.publish(u)

                if self.count > 1000:
                        rospy.loginfo('reached counter!!')
                        rospy.signal_shutdown('reach counter')
                elif self.GoalInfo.set(self.connected_system.ego.curr_state)<0:
                        rospy.loginfo('reached Goal set!!')
                        rospy.signal_shutdown('reached GoalInfo h')

        def cbf_controller_compute(self):
                ego = self.connected_system.ego
                cbf_list = self.connected_system.cbf_list
                x_r = ego.curr_state
                x_o = []
                for CBF in cbf_list:
                        x_o.append(CBF.agent.curr_state)
                u_s = ego.inputs
                # if self.count>3:
                # x_o_pre = np.array(self.trajs.actors[len(self.trajs.actors)-4])
                # # x_o_2pre = np.array(self.trajs.actors[len(self.trajs.actors)-3])
                # dt = self.trajs.time[len(self.trajs.time)-1]-self.trajs.time[len(self.trajs.time)-4]
                # u_o = (x_o[:,0:2]-x_o_pre[:,0:2])/dt
                # else:
                # u_o = np.zeros((len(x_o),len(self.robot.u_o)))

                cbf_list = cbf_list
                GoalInfo = self.GoalInfo
                Map = self.MapInfo

                UnsafeList = []
                Dists = []
                for CBF in cbf_list:
                        Dist = CBF.BF.h(x_r, CBF.agent.curr_state)
                        Dists.append(Dist)
                        if Dist<self.IncludeRadius:
                                UnsafeList.append(CBF)
                        ai = 1
                if min(Dists)<0:
                        InUnsafe = 1
                else:
                        InUnsafe = 0
                minDist = min(Dists)
                minJ = np.where(Dists == minDist)

                # numQPvars = len(u_s)+len(UnsafeList)+len(Map.h)+1
                # numConstraints = 2*len(u_s)+2*len(UnsafeList)+len(Map.h)+2

                # A = np.zeros((numConstraints,numQPvars))
                # b = np.zeros(numConstraints)

                # for j in range(len(UnsafeList)):
                #         # CBF Constraints
                #         A[2*j, np.arange(len(u_s))]  = UnsafeList[j].LHS(x_r, UnsafeList[j].agent.curr_state)[0]
                #         A[2*j, len(u_s)+j] = -1
                #         b[2*j] = UnsafeList[j].RHS(x_r, UnsafeList[j].agent.curr_state)
                #         A[2*j+1, len(u_s)+j] = -1
                #         b[2*j+1] = 0




                # # Adding U constraint
                # A[2*len(UnsafeList),0] = 1; b[2*len(UnsafeList)] = ego.input_range[0,1]
                # A[2*len(UnsafeList)+1,0] = -1;  b[2*len(UnsafeList)+1] = -ego.input_range[0,0]
                # A[2*len(UnsafeList)+2,1] = 1; b[2*len(UnsafeList)+2] = ego.input_range[1,1]
                # A[2*len(UnsafeList)+3,1] = -1; b[2*len(UnsafeList)+3] = -ego.input_range[1,0]

                # # Adding map constraints
                # for j in range(len(Map.h)):
                #         A[2*len(UnsafeList)+2*len(u_s)+j, np.arange(len(u_s))] = Map.LHS[j](x_r)[0]
                #         A[2*len(UnsafeList)+2*len(u_s)+j, len(u_s)+len(UnsafeList)+j] = -1
                #         b[2*len(UnsafeList)+2*len(u_s)+j-1] = Map.RHS[j](x_r)

                # # Adding GoalInfo based Lyapunov !!!!!!!!!!!!!!!!! Needs to be changed for a different example 
                # A[2*len(UnsafeList)+2*len(u_s)+len(Map.h),0:2] = [GoalInfo.Lyap(x_r,[1,0]), GoalInfo.Lyap(x_r,[0, 1])]
                # A[2*len(UnsafeList)+2*len(u_s)+len(Map.h),-1] = -1
                # b[2*len(UnsafeList)+2*len(u_s)+len(Map.h)] = 0
                # A[2*len(UnsafeList)+2*len(u_s)+len(Map.h)+1,-1] = 1
                # b[2*len(UnsafeList)+2*len(u_s)+len(Map.h)+1] = np.finfo(float).eps+1

                # H = np.zeros((numQPvars,numQPvars))
                # H[0,0] = 0
                # H[1,1] = 0

                # ff = np.zeros((numQPvars,1))
                # for j in range(len(UnsafeList)):
                #         ff[len(u_s)+j] = 10000      # To reward not using the slack variables when not required

                # for j in range(len(Map.h)):
                #         ff[len(u_s)+len(UnsafeList)+j] = 1
                # ff[-1] = np.ceil(self.count/100.0)

                numQPvars = len(u_s)+len(UnsafeList)+len(Map.BF.h)+1
                numConstraints = 2*len(u_s)+len(UnsafeList)+len(Map.BF.h)+2

                A = np.zeros((numConstraints,numQPvars))
                b = np.zeros(numConstraints)

                for j in range(len(UnsafeList)):
                        # CBF Constraints
                        x_o = UnsafeList[j].agent.curr_state
                        try:
                                dx = np.array(UnsafeList[j].agent.state_traj[-5:-1][-1][1])-np.array(UnsafeList[j].agent.state_traj[-5:-1][0][1])
                                dt = UnsafeList[j].agent.state_traj[-5:-1][-1][0]-UnsafeList[j].agent.state_traj[-5:-1][0][0]
                                mean_inp = dx/dt
                        except:
                                mean_inp = [0,0,0]

                        A[j, np.arange(len(u_s))]  = UnsafeList[j].BF.LHS(x_r, x_o)[0]
                        A[j, len(u_s)+j] = -1
                        b[j] = UnsafeList[j].BF.RHS(x_r, x_o, mean_inp)


                # Adding U constraint
                A[len(UnsafeList),0] = 1; b[len(UnsafeList)] = ego.input_range[0,1]
                A[len(UnsafeList)+1,0] = -1;  b[len(UnsafeList)+1] = -ego.input_range[0,0]
                A[len(UnsafeList)+2,1] = 1; b[len(UnsafeList)+2] = ego.input_range[1,1]
                A[len(UnsafeList)+3,1] = -1; b[len(UnsafeList)+3] = -ego.input_range[1,0]

                # Adding map constraints
                for j in range(len(Map.BF.h)):
                        A[len(UnsafeList)+2*len(u_s)+j, np.arange(len(u_s))] = Map.BF.LHS[j](x_r)[0]
                        A[len(UnsafeList)+2*len(u_s)+j, len(u_s)+len(UnsafeList)+j] = -1
                        b[len(UnsafeList)+2*len(u_s)+j] = Map.BF.RHS[j](x_r)

                # Adding GoalInfo based Lyapunov !!!!!!!!!!!!!!!!! Needs to be changed for a different example
                A[len(UnsafeList)+2*len(u_s)+len(Map.BF.h),0:2] = [GoalInfo.Lyap(x_r,[1,0]), GoalInfo.Lyap(x_r,[0, 1])]
                A[len(UnsafeList)+2*len(u_s)+len(Map.BF.h),-1] = -1
                b[len(UnsafeList)+2*len(u_s)+len(Map.BF.h)] = 0
                A[len(UnsafeList)+2*len(u_s)+len(Map.BF.h)+1,-1] = 1
                b[len(UnsafeList)+2*len(u_s)+len(Map.BF.h)+1] = np.finfo(float).eps+1

                H = np.zeros((numQPvars,numQPvars))
                H[0,0] = 0
                H[1,1] = 0

                ff = np.zeros((numQPvars,1))
                for j in range(len(UnsafeList)):
                        ff[len(u_s)+j] = 100      # To reward not using the slack variables when not required
                        # H[len(u_s)+j,len(u_s)+j] = 100      # To reward not using the slack variables when not required


                for j in range(len(Map.BF.h)):
                        H[len(u_s)+len(UnsafeList)+j,len(u_s)+len(UnsafeList)+j] = 1
                ff[-1] = np.ceil(self.count/100.0)





                try:
                        uq = cvxopt_solve_qp(H, ff, A, b)
                        print(uq[1])
                except ValueError:
                        uq = [0,0]
                        rospy.loginfo('Domain Error in cvx')

                if uq is None:
                        uq = [0,0]
                        rospy.loginfo('infeasible QP')

                return uq
