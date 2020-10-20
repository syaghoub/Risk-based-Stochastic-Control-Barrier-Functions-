classdef rrt_plan < handle
    %rrt planner class
    
    properties
        T_risk=1;               %risk horizon
        T_s                      %Sample time
        T_path_seg = 0.5;        %path segment duration
        max_node = 30;          %number of nodes at each iteration of planning
        radii                        %radius
        l                        %approximation coefficient
        robot_r = 0.3;
        num_obs
        state_samp_var=0.7;      %state sampling variance
        velocity_gain = 0.3;
        ang_gain = 1;
        
        %graph properties
        graph_h = [];             %graph history
        
        
        %constraints
        Lfh             %CBF inequality constraints
        Lgh 
        CBF
        Unsafes
        gamma = 100;               %CBF coefficient
        UnsafeRadius = 5;        %unsafe radius around the robot
        NodeSelect_r = 5;        %unsafe radius for node selection
        goal_dist_mult = 2;      %multiplier of goal dist in node selection
        obs_dist_mult = 1;        %multiplier of obstacle dist in node selection
        v_max                    %maximum allowed speed
        w_max                    %maximum allowed steering angle rate
        A_v                      %control constraints
        b_v
        A_w
        b_w
        
        % wall constraints
        y_r_safe
        Lfh_y_r
        Lgh_y_r
        y_l_safe
        Lfh_y_l
        Lgh_y_l
        x_r_safe
        Lfh_x_r
        Lgh_x_r
        x_l_safe
        Lfh_x_l
        Lgh_x_l
    end
    methods
        %% Method 1
        function obj=rrt_plan(T_s,num_obs,l,robot,v_max,w_max)
            
            env_bounds.y_r = -1.7;
            env_bounds.y_l = 1.5; 
            env_bounds.x_r = 1.55; 
            env_bounds.x_l = -1.6;
            
            obj.v_max = v_max;
            obj.w_max = w_max;
            obj.T_s = T_s;
            %obj.radii = radii;
            obj.l = l;
            obj.num_obs = num_obs;
            
            %Derive CBF constraints
            t = sym('t');
            r = sym('r');
            x_r_s = sym('x_r',[1,3]);
            x_o_s = sym('x_o',[1,2]);
            u_s = sym('u', [1,2]);
            obj.Unsafes = cell(num_obs,1);
            for i = 1:num_obs
                obj.Unsafes{i} = @(x_r, x_o, r) (x_r(1)-x_o(1))^2+(x_r(2)-x_o(2))^2-(r+obj.robot_r+l)^2;
                CBFder = vpa(jacobian(obj.Unsafes{i}(x_r_s(1:2),x_o_s(1:2),r),x_r_s));
                ConstCond = vpa(CBFder*robot.f(x_r_s));
                multCond = vpa(CBFder*robot.g(x_r_s));
                str1 = char(ConstCond);
                str2 = char(multCond);
                matchPattern = sprintf('%s(\\d+)', 'x_r' );
                replacePattern = sprintf('%s\\($1\\)','x_r');
                str1 = regexprep(str1,matchPattern,replacePattern);
                str2 = regexprep(str2,matchPattern,replacePattern);
                matchPattern = sprintf('%s(\\d+)','x_o');
                replacePattern = sprintf('%s\\($1\\)','x_o');
                str1 = regexprep(str1,matchPattern,replacePattern);
                str2 = regexprep(str2,matchPattern,replacePattern);
                matchPattern = sprintf('%s(\\d+)','u');
                replacePattern = sprintf('%s\\($1\\)','u');
                str2 = regexprep(str2,matchPattern,replacePattern);
                obj.Lfh{i} = str2func(['@(x_r,x_o, r) ' str1]);
                obj.Lgh{i} = str2func(['@(x_r,x_o, r) ' str2]);
            end
            % wall constraints
            % wall y_r
            obj.y_r_safe = @(x_r) x_r(2)-env_bounds.y_r;
            CBFder_y_r = vpa(jacobian(obj.y_r_safe(x_r_s(1:2)),x_r_s));
            ConstCond_y_r = vpa(CBFder_y_r*robot.f(x_r_s));
            multCond_y_r = vpa(CBFder_y_r*robot.g(x_r_s));
            str1 = char(ConstCond_y_r);
            str2 = char(multCond_y_r);
            matchPattern = sprintf('%s(\\d+)', 'x_r' );
            replacePattern = sprintf('%s\\($1\\)','x_r');
            str1 = regexprep(str1,matchPattern,replacePattern);
            str2 = regexprep(str2,matchPattern,replacePattern);
            matchPattern = sprintf('%s(\\d+)','u');
            replacePattern = sprintf('%s\\($1\\)','u');
            str2 = regexprep(str2,matchPattern,replacePattern);
            obj.Lfh_y_r = str2func(['@(x_r)' str1]);
            obj.Lgh_y_r = str2func(['@(x_r)' str2]);
            
            % wall y_l
            obj.y_l_safe = @(x_r) env_bounds.y_l-x_r(2);
            CBFder_y_l = vpa(jacobian(obj.y_l_safe(x_r_s(1:2)),x_r_s));
            ConstCond_y_l = vpa(CBFder_y_l*robot.f(x_r_s));
            multCond_y_l = vpa(CBFder_y_l*robot.g(x_r_s));
            str1 = char(ConstCond_y_l);
            str2 = char(multCond_y_l);
            matchPattern = sprintf('%s(\\d+)', 'x_r' );
            replacePattern = sprintf('%s\\($1\\)','x_r');
            str1 = regexprep(str1,matchPattern,replacePattern);
            str2 = regexprep(str2,matchPattern,replacePattern);
            matchPattern = sprintf('%s(\\d+)','u');
            replacePattern = sprintf('%s\\($1\\)','u');
            str2 = regexprep(str2,matchPattern,replacePattern);
            obj.Lfh_y_l = str2func(['@(x_r)' str1]);
            obj.Lgh_y_l = str2func(['@(x_r)' str2]);
            
            % wall x_r
            obj.x_r_safe = @(x_r) env_bounds.x_r-x_r(1);
            CBFder_x_r = vpa(jacobian(obj.x_r_safe(x_r_s(1:2)),x_r_s));
            ConstCond_x_r = vpa(CBFder_x_r*robot.f(x_r_s));
            multCond_x_r = vpa(CBFder_x_r*robot.g(x_r_s));
            str1 = char(ConstCond_x_r);
            str2 = char(multCond_x_r);
            matchPattern = sprintf('%s(\\d+)', 'x_r' );
            replacePattern = sprintf('%s\\($1\\)','x_r');
            str1 = regexprep(str1,matchPattern,replacePattern);
            str2 = regexprep(str2,matchPattern,replacePattern);
            matchPattern = sprintf('%s(\\d+)','u');
            replacePattern = sprintf('%s\\($1\\)','u');
            str2 = regexprep(str2,matchPattern,replacePattern);
            obj.Lfh_x_r = str2func(['@(x_r)' str1]);
            obj.Lgh_x_r = str2func(['@(x_r)' str2]);
            
            % wall x_l
            obj.x_l_safe = @(x_r) x_r(1)-env_bounds.x_l;
            CBFder_x_l = vpa(jacobian(obj.x_l_safe(x_r_s(1:2)),x_r_s));
            ConstCond_x_l = vpa(CBFder_x_l*robot.f(x_r_s));
            multCond_x_l = vpa(CBFder_x_l*robot.g(x_r_s));
            str1 = char(ConstCond_x_l);
            str2 = char(multCond_x_l);
            matchPattern = sprintf('%s(\\d+)', 'x_r' );
            replacePattern = sprintf('%s\\($1\\)','x_r');
            str1 = regexprep(str1,matchPattern,replacePattern);
            str2 = regexprep(str2,matchPattern,replacePattern);
            matchPattern = sprintf('%s(\\d+)','u');
            replacePattern = sprintf('%s\\($1\\)','u');
            str2 = regexprep(str2,matchPattern,replacePattern);
            obj.Lfh_x_l = str2func(['@(x_r)' str1]);
            obj.Lgh_x_l = str2func(['@(x_r)' str2]);
        end
        
        %% Method 2
        function G = planning(obj,t_start,robot,obstacle_vec)
           x_goal = robot.x_goal; 
           u_ref=zeros(2,1);
           p_trans = @(x) x+[obj.l*cos(x(3));obj.l*sin(x(3));0]; %approximate transformation function
           
           %graph
           G.node(1).pose = robot.current_state;
           for i=1:obj.num_obs
               G.node(1).x_obs{i}{1} = obstacle_vec.current_pose(:,i);
               G.node(1).x_obs_r{i}{1} = obstacle_vec.current_r(i);
           end 
           G.node(1).t_start = t_start;
           G.node(1).prev.idx = [];
           G.node(1).prev.xr = [];
           G.node(1).prev.ur = [];
           G.node(1).prev.hr = [];
           G.node(1).prev.fval = [];
           G.node(1).prev.u_ref = [];
           G.edge(1).pair=[];
           G.edge(1).distance=[];
           G.edge(1).xr=[];
           G.edge(1).ur=[];
           G.edge(1).fval=[];
           G.node_indx = 1;
           G.edge_indx = 0;
           G.node_select = 1;
           %G.node_select_dist2G =norm(G.node(G.node_select).pose(1:2)-x_goal(1:2));<------
           
           %new measure
           dist2obs = 1;
           for i=1:obj.num_obs
               if isempty(G.node(1).x_obs{i}{1})==0 && norm(G.node(G.node_select).pose(1:2)-G.node(1).x_obs{i}{1})<obj.NodeSelect_r
                  dist2obs=dist2obs+norm(G.node(G.node_select).pose(1:2)-G.node(1).x_obs{i}{1});
               end
           end 
           G.node_select_dist2G = (obj.goal_dist_mult/obj.obs_dist_mult)*norm(G.node(G.node_select).pose(1:2)-x_goal(1:2))/dist2obs;
           %new measure
           
           G.node_list(1) = 1;
           
           while (G.node_indx <= obj.max_node)   %tree expansion
               % sampling
               % vertex sampling
               v_s_ind = randi([1,length(G.node_list)]); 
               samp_ver_pose = G.node(v_s_ind).pose; 
               current_time = G.node(v_s_ind).t_start;
               
               % state sampling
               state_samp_mean = atan2((x_goal(2)-samp_ver_pose(2)),(x_goal(1)-samp_ver_pose(1)));
               samp_theta = state_samp_mean + randn*obj.state_samp_var;
               
               % reference sampling
               [u_ref(1),u_ref(2)]=ref_inp_gen_rrt(obj,samp_theta,x_goal,samp_ver_pose);
               
               
               % initialize trajectories
               ur=zeros(2,1);
               hr=zeros(obj.num_obs,1);
               fval=zeros(1,1);
               pr=zeros(3,1);
               xr=zeros(3,1);
               xr(:,1)=samp_ver_pose;
               xr_o={};
               xr_o_radii = {};
               for i=1:obj.num_obs
                   xr_o{i}{1} = G.node(v_s_ind).x_obs{i}{1}; %obstacle trace save in cell
                   xr_o_radii{i}{1} = G.node(v_s_ind).x_obs_r{i}{1};
               end
               Node_t = G.node(v_s_ind).t_start;
               
               % planning
               for q = 1:(1/obj.T_s)*obj.T_path_seg
                  
                   pr(:,q)=p_trans(xr(:,q));
                   
                   [ur(:,q),fval(:,q),fail_opt] = CBF_QP(obj,xr_o,xr_o_radii,pr,u_ref);    %solving optimization
                   if fail_opt==1
                       q = q-1;
                       break
                   end

                   Node_t=Node_t + obj.T_s;
                   xr(:,q+1)=robot.motion(xr(:,q),ur(:,q)); %robot motion prediction
                   for k=1:obj.num_obs
                       [xr_o{k}{q+1}, xr_o_radii{k}{q+1}] = next_obs_pose(obj, Node_t, obstacle_vec.predicted_bounds{k});
                       %= obj.T_s*obstacle_vec(k).f_o(xr_o{k}(:,q))+xr_o{k}(:,q);  %obstacles motion prediction (expected value)
                   end 
                   
                   if norm(xr(1:2,end)-x_goal(1:2))<0.2; break; end %Break if reached the goal
               end
               
               % update the latest obstacle predicted location and graph data
               
               %graph update
               G.node_indx = G.node_indx+1;
               G.edge_indx = G.edge_indx+1;
               G.node_list(G.node_indx) = G.node_indx;
               G.node(G.node_indx).pose = xr(:,end);
               for i=1:obj.num_obs
                   G.node(G.node_indx).x_obs{i}{1} = xr_o{i}{end};
                   G.node(G.node_indx).x_obs_r{i}{1} = xr_o_radii{i}{end};
               end 
               G.node(G.node_indx).t_start = current_time + q*obj.T_s;
               G.node(G.node_indx).prev.idx = v_s_ind;
               G.node(G.node_indx).prev.xr = xr;
               G.node(G.node_indx).prev.ur = ur;
               G.node(G.node_indx).prev.hr = hr;
               G.node(G.node_indx).prev.fval = fval;
               G.node(G.node_indx).prev.u_ref = u_ref;
               G.edge(G.edge_indx).pair=[v_s_ind;G.node_indx];
               G.edge(G.edge_indx).distance=[];
               G.edge(G.edge_indx).xr=xr;
               G.edge(G.edge_indx).ur = ur;
               G.edge(G.edge_indx).fval=fval;
               
%                if (norm(xr(1:2,end)-x_goal(1:2)) < G.node_select_dist2G)         
%                    G.node_select = G.node_indx;
%                    G.node_select_dist2G = norm(xr(1:2,end)-x_goal(1:2));   
%                end     <-------
               %new measure
               dist2obs = 1;
               for i=1:obj.num_obs
                   if isempty(G.node(G.node_indx).x_obs{i}{1})==0 && norm(xr(1:2,end)-G.node(G.node_indx).x_obs{i}{1})<obj.NodeSelect_r
                      dist2obs=dist2obs+(obj.goal_dist_mult/obj.obs_dist_mult)*norm(xr(1:2,end)-G.node(G.node_indx).x_obs{i}{1});
                   end
               end 
               if ((obj.goal_dist_mult/obj.obs_dist_mult)*norm(xr(1:2,end)-x_goal(1:2))/dist2obs < G.node_select_dist2G)         
                    G.node_select = G.node_indx;
                    G.node_select_dist2G = (obj.goal_dist_mult/obj.obs_dist_mult)*norm(xr(1:2,end)-x_goal(1:2))/dist2obs;   
               end     
               
               %new measure
           end
           obj.graph_h = [obj.graph_h  G];
        end
        
        %% Method 3
        function [xr_o, radii] = next_obs_pose(obj, curr_t, bounds)
            if curr_t*(1/obj.T_s)>length(bounds)
                xr_o = bounds{end}.center;
                radii = bounds{end}.r;
            else
                xr_o = bounds{int64(curr_t*(1/obj.T_s)+0.000001)}.center;
                radii = bounds{int64(curr_t*(1/obj.T_s)+0.000001)}.r;
            end
        end
        
        %% Method4
        function [v_ref,w_ref]=ref_inp_gen_rrt(obj,theta_ref,goal,current_pos)
            %v_ref=rand*norm(goal-current_pos(1:2));
            % v_ref = abs(velocity_gain*angdiff(current_pos(3),theta_ref));
            v_ref=rand*obj.v_max;
            %v_ref = 1;
            w_ref = obj.ang_gain*angdiff(current_pos(3),theta_ref);
        end
        
        %% Method 5
        function [ur, fval, fail_opt] = CBF_QP(obj,xr_o,xr_o_radii,pr,u_ref)
           curr_xr = pr(:,end); 
           
           options =  optimset('Display','off','MaxIter', 2000);
           UnsafeList = [];
           Dists = [];
           % selecting close obstacles in the range of UnsafeRadius
           for j = 1:obj.num_obs
               if isempty(xr_o{j}{end})~=1
                    Dists(j) = sqrt(obj.Unsafes{j}(curr_xr,  xr_o{j}{end},0));
                    if Dists(j)<obj.UnsafeRadius
                        UnsafeList = [UnsafeList ,j];
                    end
               end
           end

           A = [];  %constraint
           b =[];   %constraint
           H = [];  %weight
           ff = []; %weight
           
           % constraints setup
           % Dynamic obstacles constraint
           if isempty(UnsafeList)~=1
               for j = 1:length(UnsafeList)
                   %CBF constraint construction
                   obs_num=zeros(1,length(UnsafeList));
                   obs_num(j)=-1;
                   % CBF Constraints
                   A(2*j-1,:) = [-obj.Lgh{UnsafeList(j)}(curr_xr,  xr_o{UnsafeList(j)}{end}, xr_o_radii{UnsafeList(j)}{end}) obs_num]; % multiplier of u , bi
                   b(2*j-1) = obj.gamma * obj.Unsafes{UnsafeList(j)}(curr_xr,  xr_o{UnsafeList(j)}{end},xr_o_radii{UnsafeList(j)}{end})...
                       + obj.Lfh{UnsafeList(j)}(curr_xr, xr_o{UnsafeList(j)}{end},xr_o_radii{UnsafeList(j)}{end});  
                   % Constraints on bi to satisfy pi risk
                   obs_num(j)=1;
                   A(2*j,:) = [0 0 obs_num];
                   b(2*j) = 0;
               end
           end
           
           % wall constraints
           if ((curr_xr(1)<-1.6) || (curr_xr(1)>1.55))
               A(end+1,1:2) = -obj.Lgh_y_r(curr_xr);
               b(end+1) = obj.gamma * obj.y_r_safe(curr_xr)+ obj.Lfh_y_r(curr_xr);
               A(end+1,1:2) = -obj.Lgh_y_l(curr_xr);
               b(end+1) = obj.gamma * obj.y_l_safe(curr_xr)+ obj.Lfh_y_l(curr_xr);
           else
               A(end+1,1:2) = -obj.Lgh_y_r(curr_xr);
               b(end+1) = obj.gamma * obj.y_r_safe(curr_xr)+ obj.Lfh_y_r(curr_xr);
               A(end+1,1:2) = -obj.Lgh_x_r(curr_xr);
               b(end+1) = obj.gamma * obj.x_r_safe(curr_xr)+ obj.Lfh_x_r(curr_xr);
               A(end+1,1:2) = -obj.Lgh_x_l(curr_xr);
               b(end+1) = obj.gamma * obj.x_l_safe(curr_xr)+ obj.Lfh_x_l(curr_xr);
           end
           
           % control constraints
           A(end+1,1) = 1; b(end+1) = obj.v_max; %max allowed speed
           A(end+1,1) = -1;  b(end+1) = obj.v_max;
           A(end+1,2) = 1; b(end+1) = obj.w_max;
           A(end+1,2) = -1; b(end+1) = obj.w_max;
           
           
           % optimization weights
           H = [1000 0 zeros(1,length(UnsafeList));0 100000 zeros(1,length(UnsafeList));zeros(length(UnsafeList),length(u_ref)+length(UnsafeList))];
           ff = [-2*1000*u_ref(1);-2*100000*u_ref(2);1.5*ones(length(UnsafeList),1)];
           
           % optimization
           try
               [u,fval,exitflag,out]= quadprog(H, ff, A, b,[],[],[],[],[],options);
           catch flag
               fail_opt = 1;
               return
           end
           fail_opt=0;
           if ~isempty(u)
              ur=u(1:2);
           else
              ur=zeros(2,1);
              fval=0;
              fail_opt = 1;
           end
        end
    end
end





