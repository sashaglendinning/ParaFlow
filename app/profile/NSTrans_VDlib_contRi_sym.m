classdef NSTrans_VDlib_contRi_sym < ode_continuation
    properties (GetAccess=public, SetAccess=private)   
        Re
        Pe_s
        Q
        Gamma 
    end
    methods
        %% Constructor
        function obj=NSTrans_VDlib_contRi_sym(mesh_obj,settings,h,num_iter,save_iter,x0)
            if nargin<4
                error('osp_Hbase_iter_const_continRi: Not enough Input argument');
            else
                super_args{5}=num_iter;
                super_args{4}=h;
                super_args{3}="Gamma";
                super_args{2}=settings;
                super_args{1}=mesh_obj;
            end
            switch nargin
                case 5
                    super_args{6}=save_iter;
                case 6
                    super_args{6}=save_iter;
                    super_args{7}=x0;
                otherwise
                    error('incorrect number of inputs');
            end
            obj=obj@ode_continuation(super_args{:});    
        end
        %% Inherited Abstract class
        function obj=set_para(obj,varargin)
            narginchk(2,23);
            p=inputParser;
            p.KeepUnmatched=true;
            p.PartialMatching=false;
            p.addParameter('Re',obj.Re);
            p.addParameter('Pe_s',obj.Pe_s);
            p.addParameter('Q',obj.Q);
            p.addParameter('Gamma',obj.Gamma);

            p.addParameter('Nnewton',obj.Nnewton);
            p.addParameter('epsilon',obj.epsilon);
            p.addParameter('min_iter',obj.min_iter);
            
            p.addParameter('limiter_value',obj.limiter_value);
            p.addParameter('limiter_index',obj.limiter_index);
            
            p.addParameter('h',obj.h);

            p.addParameter('disp_iter',obj.disp_iter);

            p.parse(varargin{:});
            
            obj.Re=p.Results.Re;
            obj.Pe_s=p.Results.Pe_s;
            obj.Q=p.Results.Q;
            obj.Gamma=p.Results.Gamma; % Starting Value of Gamma
          
            obj.Nnewton=p.Results.Nnewton;
            obj.epsilon=p.Results.epsilon;
            obj.min_iter=p.Results.min_iter;

            obj.limiter_value=p.Results.limiter_value;
            obj.limiter_index=p.Results.limiter_index;

            obj.h=p.Results.h;
            
            obj.disp_iter=p.Results.disp_iter;
        end
        function [res,lhs]=residue_infun(obj,y,yp,lib_value,z)
            D11=lib_value.D11*obj.Pe_s^2;
            V1=lib_value.V1*obj.Pe_s;
            % Extracting mesh_obj
            D1M=obj.mesh_obj.D(1);
            D2M=obj.mesh_obj.D(2);
            N=double(obj.mesh_obj.N);
            wint=obj.mesh_obj.wint;
            
            % Extracting x
            G=y(1);
            U0=y(2:N+1);
            N0=y(N+2:2*N+1);
            Gamma=y(2*N+2);
            
            % Differentiating
            DU0=D1M*U0;
            D2U0=D2M*U0;
            DN0=D1M*N0;
            % D2N0=D2M*N0;
            
            % Residue of equation 1 (Flow Rate)
            lhs1=(wint*U0)-obj.Q/2;
            if obj.Q==0
                res1=abs(lhs1);
            else
                res1=abs(lhs1)/obj.Q*2;
            end

            % Residue of equation 2 (Navier-Stokes)
            Nbar=ones(N,1)/2;
            lhs2=-G+1/obj.Re*D2U0-Gamma*(N0-Nbar);
            lhs2(end)=0;
            lhs2(1)=0;
            if any(U0)  && sqrt(U0'*diag(wint)*U0)>5e-4
                res2=sqrt(lhs2'*diag(wint)*lhs2)/sqrt(U0'*diag(wint)*U0);
            else
                res2=sqrt(lhs2'*diag(wint)*lhs2);
            end
            lhs2(end)=DU0(end);
            lhs2(1)=U0(1);
            
            % Residue of equation 3 (Transport, integrated)
            lhs3=D11.*DN0-V1.*N0;
            lhs2(end)=0;
            res3=sqrt(lhs3'*diag(wint)*lhs3)/sqrt(N0'*diag(wint)*N0);
            lhs3(end)=DN0(end);

            % Residue of equation 4 (Conservation of N)
            lhs4=(wint*N0)-1/2;
            res4=abs(lhs4);

            % Residue of Parameter orthogonal vector
            lhs5=z*(y-yp);
            res5=abs(lhs5);

            % Combining Residues
            lhs=[lhs1; lhs2; lhs4;lhs3(2:end);lhs5];
            res=res1+res2+res3+res4+res5;
        end
        function lib_value = lib_read(obj,y)
            %V1 is the interpolated <er> vector in the N points, so for r between 1 and 0.
            %D11 is the diffusivity vector between 1 and 0.
            %DV1 and DD11 are the matrix whose diagonal terms are dV1/dS and dD11/dS
            persistent loadmat
            if isempty(loadmat)
                loadmat=load('./GTD3D_libp_beta22_fit.mat','e1fitobject','D11fitobject');
            end
            %% Compute S
            U0=y(2:obj.mesh_obj.N+1);
            S=obj.mesh_obj.D(1)*U0;
            %% Interpolate
            lib_value.V1=loadmat.e1fitobject(S);
            lib_value.D11=loadmat.D11fitobject(S);
            lib_value.DV1=differentiate(loadmat.e1fitobject,S);
            lib_value.DD11=differentiate(loadmat.D11fitobject,S); 
        end
        function dfdx=dfdx_infun(obj,y,lib_value,z)
            V1=lib_value.V1*obj.Pe_s;
            DV1=lib_value.DV1*obj.Pe_s;
            D11=lib_value.D11*obj.Pe_s^2;
            DD11=lib_value.DD11*obj.Pe_s^2;
            % Mesh and Differential Matrices
            D1M=obj.mesh_obj.D(1);
            D2M=obj.mesh_obj.D(2);
            N=obj.mesh_obj.N;
            wint=obj.mesh_obj.wint;
            
            % Extracting x
            N0=y(N+2:2*N+1);
            DN0=D1M*N0;
            Gamma=y(2*N+2);

            % Preparing Utils
            Nbar=ones(N,1)/2;

            % Preparing Jacobian 
            % (Flow Rate)
            dfdx1 = [0  wint zeros(1,N+1)];
            % (Navier-Stokes)
            dfdx2 = [-ones(obj.mesh_obj.N,1)  1/obj.Re*(D2M)  -Gamma*obj.mesh_obj.I -(N0-Nbar)];
            % boundary conditions for u
            dfdx2(1,:) = 0;
            dfdx2(N,:) = 0;
            dfdx2(1,2) = 1.;                 % U0(x = 1)=0
            dfdx2(N,2:N+1) = D1M(end,:);     %DU0(x = 0)=0
            
            % (Transport)
            Lnv=diag(DN0.*DD11)...
                -diag(N0.*DV1);
            Lnn=diag(D11)*D1M-diag(V1);
            
            dfdx3 = [zeros(N,1)  Lnv  Lnn  zeros(N,1)] ;
            % boundary conditions for N
            dfdx3(N,:) = 0;
            dfdx3(N,N+2:2*N+1) = D1M(end,:);     %DN0(x = 0)=0

            % (Conservation of N)
            dfdx4 = [0  zeros(1,N) wint 0];
            
            % Combining Jacobians
            dfdx=[dfdx1; dfdx2; dfdx4; dfdx3(2:end,:); z];
        end
        function x0=get_initial_solution(obj)
            settings.Re=obj.Re;
            settings.Pe_s=obj.Pe_s;
            settings.Gamma=obj.Gamma;
            settings.Q=obj.Q;
            prof_obj=NSTrans_VDlib_sym(obj.mesh_obj,settings);
            prof_obj=prof_obj.solve();
            x0=prof_obj.prof;
        end
    end
end