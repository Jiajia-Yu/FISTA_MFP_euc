function [rho,mx,my,outs] = func_mfg(rho0,rho1,opts)

%% parameters
% time and space parameters
if length(size(rho0))==2
    [nx,ny] = size(rho0);
    rho0 = reshape(rho0,1,nx,ny);
    rho1 = reshape(rho1,1,nx,ny);
else
    [~,nx,ny] = size(rho0);
end
nxm = nx-1;
dx = 1/nx;
nym = ny-1;
dy = 1/ny;
if isfield(opts,'nt') nt = opts.nt; else nt = 20; end
ntm = nt-1;
dt = 1/nt;

% parameters of model
lambda_L = opts.lambda_L ;
lambda_E = opts.lambda_E;
lambda_P = opts.lambda_P;
lambda_G = opts.lambda_G;
Qx = reshape(opts.Qx,1,nx,ny);
Qx = repmat(Qx,nt,1,1);
Gx = reshape(opts.Gx,1,nx,ny);

% inital value of rho and mx
if isfield(opts,'rho') xrho_km1 = opts.rho; else xrho_km1 = ones(nt,nx,ny); end
if isfield(opts,'mx')  xmx_km1  = opts.mx;  else xmx_km1  = ones(nt,nxm,ny); end
if isfield(opts,'my')  xmy_km1  = opts.my;  else xmy_km1  = ones(nt,nx,nym); end

% stop criteria
if isfield(opts,'maxit') maxit = opts.maxit; else maxit = 5e3;  end
if isfield(opts,'tol')   tol   = opts.tol;   else tol   = 1e-6; end

% parameter for backtracking
if isfield(opts,'L0')    L0    = opts.L0; else L0  = 10; end
if isfield(opts,'eta')   eta = opts.eta;  else eta = 1.2; end 
if isfield(opts,'sub_maxit') sub_maxit = opts.sub_maxit; else sub_maxit = 5; end

% for solving Poisson equation
lap_t = reshape((2 - 2*cos(pi*(2*nt-1:-2:1)/(2*nt+1)))/dt/dt,nt,1,1);
lap_x = reshape((2 - 2*cos(pi*(0:nx-1)/nx))/dx/dx,1,nx,1);
lap_y = reshape((2 - 2*cos(pi*(0:ny-1)/ny))/dy/dy,1,1,ny);
lap = repmat(lap_t,1,nx,ny) + repmat(lap_x,nt,1,ny) + repmat(lap_y,nt,nx,1);

% matDt = spdiags(ones(nt,1)*[-1/dt,1/dt],[-1,0], nt,nt);
% matDx = spdiags(ones(nx,1)*[-1/dx,1/dx],[-1,0], nx,nxm);
% matDy = spdiags(ones(ny,1)*[-1/dy,1/dy],[-1,0], ny,nym);
% LHS = kron(kron(speye(ny),speye(nx)),matDt*matDt') ...
%      +kron(kron(speye(ny),matDx*matDx'),speye(nt)) ...
%      +kron(kron(matDy*matDy',speye(nx)),speye(nt));
% dLHS = decomposition(LHS);

%% initialization
objs = zeros(maxit,1);
projerrs = zeros(maxit,1);
stepsizes = zeros(maxit,1);
ress = zeros(maxit,1);

yrho = xrho_km1;
ymx = xmx_km1;
ymy = xmy_km1;
obj_km1 = compObj(yrho,ymx,ymy);

t_km1 = 1;
%% main iteration
for nit = 1:maxit
    % backtracking
    [grad_rho,grad_mx,grad_my] = compGrad(yrho,ymx,ymy);
    
    sub_nit = 0;
    L = L0;
    while sub_nit < sub_maxit
        [xrho_k,xmx_k,xmy_k,projerr] = compProj(yrho - 1/L*grad_rho, ...
                              ymx - 1/L*grad_mx,ymy  - 1/L*grad_my);
        
        obj_k = compObj(xrho_k,xmx_k,xmy_k);
        diff_rho = xrho_k - yrho;
        diff_mx  = xmx_k - ymx;
        diff_my  = xmy_k - ymy;
%         G = obj_km1 + sum(grad_rho.*diff_rho,'all') ...
%                     + sum(grad_mx .*diff_mx, 'all') ...
%                     + sum(grad_my .*diff_my, 'all') ...
%                 + L/2*sum(diff_rho.*diff_rho,'all') ...
%                 + L/2*sum(diff_mx .*diff_mx, 'all') ...
%                 + L/2*sum(diff_my .*diff_my, 'all');
        G = compObj(yrho,ymx,ymy) ...
                    + sum(grad_rho.*diff_rho,'all') ...
                    + sum(grad_mx .*diff_mx, 'all') ...
                    + sum(grad_my .*diff_my, 'all') ...
                + L/2*sum(diff_rho.*diff_rho,'all') ...
                + L/2*sum(diff_mx .*diff_mx, 'all') ...
                + L/2*sum(diff_my .*diff_my, 'all');
        
        if obj_k <= G
            break
        end
        sub_nit = sub_nit + 1;
        L = L*eta;
    end
        
    % update variables
    t_k = (1 + sqrt(1+4*t_km1^2))/2;
    w_k = (t_km1-1)/t_k;
    drho = xrho_k-xrho_km1;
    dmx = xmx_k -xmx_km1;
    dmy = xmy_k -xmy_km1;
    yrho = max( xrho_k + w_k*drho,0.1);
%     yrho = xrho_k + w_k*drho;
    ymx  = xmx_k  + w_k*dmx;
    ymy  = xmy_k  + w_k*dmy;
    
    t_km1 = t_k;
    obj_km1 = obj_k;
    xrho_km1 = xrho_k;
    xmx_km1 = xmx_k;
    xmy_km1 = xmy_k;
    
    objs(nit) = obj_k*dx*dy;
    projerrs(nit) = projerr;
    stepsizes(nit) = 1/L;
    
    res = dt*dx*dy*(norm(drho(:))+norm(dmx(:))+norm(dmy(:)));
    ress(nit) = res;
    if res < tol
        break
    end
    
    if isnan(obj_k) || isinf(obj_k)
        fprintf('blow up at iter %d\n', nit);
        rho = cat(1,rho0,xrho_k);
        mx = cat(2,zeros(nt,1,ny),xmx_k,zeros(nt,1,ny));
        my = cat(3,zeros(nt,nx,1),xmy_k,zeros(nt,nx,1));
        outs.objs = objs(1:nit);
        outs.projerrs = projerrs(1:nit);
        outs.stepsizes = stepsizes(1:nit);
        outs.ress = ress(1:nit);
        return
    end

end

%% copy results
rho = cat(1,rho0,xrho_k);
mx = cat(2,zeros(nt,1,ny),xmx_k,zeros(nt,1,ny));
my = cat(3,zeros(nt,nx,1),xmy_k,zeros(nt,nx,1));
outs.objs = objs(1:nit);
outs.projerrs = projerrs(1:nit);
outs.stepsizes = stepsizes(1:nit);
outs.ress = ress(1:nit);

%% functions

    function obj = compObj(rho,mx,my)
        rho_end = max(rho(end,:,:),0.01);
        rho = cat(1,rho0,rho);
        mx = cat(2,zeros(nt,1,ny),mx,zeros(nt,1,ny));
        my = cat(3,zeros(nt,nx,1),my,zeros(nt,nx,1));
        rho = It(rho);
        mx = Ix(mx);
        my = Iy(my);
%         ind = rho > 1e-8;
        ind = rho > 0;
%         ind = rho ~=0;
        
        obj = lambda_L*sum( (mx(ind).^2+my(ind).^2)./rho(ind) )*dt ...
             +lambda_E*sum( rho(ind).*log(rho(ind)) )*dt ...
             +lambda_P*sum( rho(ind).*Qx(ind))*dt ...
        	 +lambda_G*sum( rho_end.*(Gx+log(rho_end)),'all' );
    end

    function [grad_rho,grad_mx,grad_my] = compGrad(rho,mx,my)
        rho_end = rho(end,:,:);
        rho = cat(1,rho0,rho);
        mx = cat(2,zeros(nt,1,ny),mx,zeros(nt,1,ny));
        my = cat(3,zeros(nt,nx,1),my,zeros(nt,nx,1));
        rho = It(rho);
        mx = Ix(mx);
        my = Iy(my);
%         ind = rho > 1e-8;
        ind = rho > 0;
%         ind = rho ~=0;
        
        grad_rho = zeros(size(rho));
        grad_mx = zeros(size(mx));
        grad_my = zeros(size(my));
        
        grad_rho(ind) = - lambda_L*(mx(ind).^2+my(ind).^2)./rho(ind).^2/2*dt ...
            + lambda_E*(1+log(rho(ind)))*dt + lambda_P*Qx(ind)*dt;
        grad_mx(ind) = lambda_L*mx(ind)./rho(ind)*dt;
        grad_my(ind) = lambda_L*my(ind)./rho(ind)*dt;
        
        grad_rho_end = 0.5*grad_rho(end,:,:) + lambda_G*(Gx+log(rho_end)+1);
        grad_rho = cat(1, It(grad_rho),grad_rho_end);
        grad_mx = Ix(grad_mx);
        grad_my = Iy(grad_my);
    end

    function [rho_proj,mx_proj,my_proj,projerr] = compProj(rho,mx,my)
        rho_proj = rho;
        mx_proj  = mx;
        my_proj  = my;
        rho = cat(1,rho0,rho);
        mx = cat(2,zeros(nt,1,ny),mx,zeros(nt,1,ny));
        my = cat(3,zeros(nt,nx,1),my,zeros(nt,nx,1));
        
        phi = trans_dct( Dt(rho)+Dx(mx)+Dy(my) )./lap;
        phi = trans_idct(phi);
        
%         RHS = reshape(Dt(rho) + Dx(mx) + Dy(my),[],1);
%         phi = reshape(dLHS\RHS,nt,nx,ny);
        
        rho_proj(1:end-1,:,:) = rho_proj(1:end-1,:,:) + Dt(phi);
        rho_proj(end,:,:) = rho(end,:,:) - phi(end,:,:)/dt;
        mx_proj  = mx_proj  + Dx(phi);
        my_proj  = my_proj  + Dy(phi);
        
        
        projerr = Dt(cat(1,rho0,rho_proj))+...
                  Dx(cat(2,zeros(nt,1,ny),mx_proj,zeros(nt,1,ny)))+...
                  Dy(cat(3,zeros(nt,nx,1),my_proj,zeros(nt,nx,1)));
        projerr = max(abs(projerr),[],'all');
  
    end

    function DtA = Dt(A)
        DtA = (A(2:end,:,:) - A(1:end-1,:,:))/dt;
    end

    function DxA = Dx(A)
        DxA = (A(:,2:end,:) - A(:,1:end-1,:))/dx;
    end

    function DyA = Dy(A)
        DyA = (A(:,:,2:end) - A(:,:,1:end-1))/dy;
    end

    function ItA = It(A)
        ItA = (A(1:end-1,:,:) + A(2:end,:,:))/2;
    end

    function IxA = Ix(A)
        IxA = (A(:,1:end-1,:) + A(:,2:end,:))/2;
    end

    function IyA = Iy(A)
        IyA = (A(:,:,1:end-1) + A(:,:,2:end))/2;
    end

end