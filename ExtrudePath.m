classdef ExtrudePath < dmodel.Node
% ExtrudePath  Pasta machine!
%
% Usage: ExtrudePath(named parameters)
%
% Named parameters:
%   Path                function f(p,t) returning row vectors [x y z]
%   X                   function f(p) returning x coords of cross-section
%   Y                   function f(p) returning y coords of cross-section
%   U                   function f(p) returning 3-vectors along "x"
%   V                   function f(p) returning 3-vectors along "y"
%   Closed              if true, makes an oroborus
    
    properties
        xFunc = [];
        yFunc = [];
        pathFunc = [];  % map [0 1] to [x y z]
        fwdFunc = [];
        uFunc = [];    % map [0 1] to [ux uy uz]
        vFunc = [];
        isClosed = false;
        
    end
    
    methods
        function obj = ExtrudePath(varargin)
            
            X.X = [];
            X.Y = [];
            X.Path = [];
            X.U = [];
            X.V = [];
            X.Closed = false;
            X = parseargs(X, varargin{:});
            
            if ~isa(X.X, 'function_handle')
                error('X must be a function handle');
            end
            
            if ~isa(X.Y, 'function_handle')
                error('Y must be a function handle');
            end
            
            if ~isa(X.Path, 'function_handle')
                error('Path must be a function handle');
            end
            
            if ~isempty(X.U) && ~isa(X.U, 'function_handle')
                error('U must be a function handle');
            end
            
            if ~isempty(X.V) && ~isa(X.V, 'function_handle')
                error('V must be a function handle');
            end
            
            obj.xFunc = X.X;
            obj.yFunc = X.Y;
            obj.pathFunc = X.Path;
            obj.uFunc = X.U;
            obj.vFunc = X.V;
            obj.isClosed = X.Closed;
        end
        
        function [xBot yBot tris] = bottomFace(obj, params)
            
            % Make the bottom face
            xBot = obj.xFunc(params);
            yBot = obj.yFunc(params);
            
            if size(xBot, 2) ~= 1 || size(yBot, 2) ~= 1
                error('X and Y must return column vectors');
            end
            
            if nargout > 2

                profile = [xBot yBot];
                outerConstraint = [(1:numel(xBot))', [2:numel(xBot), 1]'];
                dt = DelaunayTri(profile, outerConstraint);
                inside = inOutStatus(dt);

                tris = dt.Triangulation(inside,:);
            end
            
            %DxBot = t6.model.jacobian(obj.xFunc, params);
            %DyBot = t6.model.jacobian(obj.yFunc, params);
            
        end
        
        function allFaces = faces(obj, tris, numEdges, numRings)
            
            v0 = 1:numEdges;
            v1 = [2:numEdges, 1];
            v2 = v1 + numEdges;
            v3 = v0 + numEdges;

            ringFaces = [v0' v1' v2'; v0' v2' v3'];
            
            if obj.isClosed
                allFaces = zeros(numEdges*2*(numRings+1), 3);
            else
                numEndFaces = size(tris, 1);
                allFaces = zeros(numEdges*2*numRings + 2*numEndFaces, 3);
            end

            facesPerRing = 2*numEdges;
            for rr = 1:numRings
                allFaces((rr-1)*facesPerRing + (1:facesPerRing), :) = ...
                    ringFaces + (rr-1)*numEdges;
            end

            % Add end faces.
            
            if obj.isClosed
                rr = numRings+1;
                allFaces( (rr-1)*facesPerRing + (1:facesPerRing), :) = ...
                    [v0' + (rr-1)*numEdges, v1' + (rr-1)*numEdges, v1'; ...
                    v0' + (rr-1)*numEdges, v1', v0'];
            else
                allFaces(numRings*facesPerRing + (1:numEndFaces), :) = fliplr(tris);
                allFaces(numRings*facesPerRing + numEndFaces + (1:numEndFaces), :) = ...
                    tris + numRings*numEdges;
            end
            
        end
        
        function v = allVertices(obj, params)
            
            [xBot yBot] = obj.bottomFace(params);
            v = obj.vertices(params, xBot, yBot);
            
        end
        
        function v = vertices(obj, params, xBot, yBot)
            
            % 1. calculate profile vertices
            % 2. calculate spine path
            % 3. calculate the rotation matrix at each position
            % 4. arrange vertices as single column (right?)
            
            path = obj.pathFunc(params);
            
            if any(isnan(path(:)))
                keyboard;
            end
            fwd = centeredDiff(path, 2);
            fwd = bsxfun(@times, fwd, 1./sqrt(sum(fwd.^2,1)));
            
            if ~isempty(obj.uFunc)
                u = obj.uFunc(params);
            end
            
            if ~isempty(obj.vFunc)
                v = obj.vFunc(params);
            end
            
            if ~exist('u', 'var') && ~exist('v', 'var')
                [u v] = obj.normalBasis(fwd);
            elseif ~exist('u', 'var')
                u = cross(v, fwd, 1);
            elseif ~exist('v', 'var')
                v = cross(fwd, u, 1);
            end
            
            % Build local basis func!
            
            uTensor = reshape(u, 3, 1, []);
            vTensor = reshape(v, 3, 1, []);
            pTensor = reshape(path, 3, 1, []);
            
            A = cat(2, uTensor, vTensor, pTensor);
            xy = [xBot yBot ones(size(xBot))];
            
            stretchOut = @(A) A(:);
            v = stretchOut(dmodel.multTensor(A, xy, 2));
        end
        
        
        function m = meshes(obj, varargin)
            import dmodel.*
            
            if nargin > 1
                params = varargin{1};
            else
                params = [];
            end
            
            % Check all the functions!
            szX = size(obj.xFunc(params));
            szY = size(obj.yFunc(params));
            if ~isequal(szX, szY)
                error(['Waveguide X and Y cross section functions must ', ...
                    ' return same number of vertices']);
            end
            
            sz = size(obj.pathFunc(params));
            numKnots = sz(2);
            if sz(1) ~= 3
                error('Path function must return 3xN array!');
            end
            
            if ~isempty(obj.uFunc)
                sz = size(obj.uFunc(params));
                if sz(1) ~= 3
                    error('U function must return 3xN array!');
                elseif sz(2) ~= numKnots
                    error('U and Path functions return different array sizes!');
                end
            end
            
            if ~isempty(obj.vFunc)
                sz = size(obj.vFunc(params));
                if sz(1) ~= 3
                    error('V function must return 3xN array!');
                elseif sz(2) ~= numKnots
                    error('V and Path functions return different array sizes!');
                end
            end
            
            [xBot, ~, tris] = obj.bottomFace(params);
            
            vertFunc = @(p) obj.allVertices(p);
            
            myVerts = vertFunc(params);
            myFaces = obj.faces(tris, length(xBot), numKnots-1);
            
            myJacobian = jacobian(vertFunc, params);
            
            m = { Mesh(myVerts, myFaces, myJacobian) };
        end
        
        
        function [u v n b] = normalBasis(obj, fwd)
            fwd = unit(fwd);
            n = unit(centeredDiff(fwd, 2));  % principal normal
            b = unit(cross(fwd, n, 1));      % binormal
            tnb = cat(3, fwd, n, b);

            n_ahead = unit(cross(b(:,1:end-1), fwd(:,2:end), 1));
            tnb_ahead = cat(3, fwd(:,2:end), n_ahead, b(:,1:end-1));

            u = 0*fwd;
            firstNormalPlane = null(fwd(:,1)');
            u(:,1) = firstNormalPlane(:,1);

            for pp = 2:size(fwd, 2)

                U = squish(tnb(:,pp-1,:));
                V = squish(tnb_ahead(:,pp-1,:));

                if any(isnan(U(:))) || any(isnan(V(:)))
                    u(:,pp) = u(:,pp-1);
                else
                    u(:,pp) = V*inv(U)*u(:,pp-1);
                end

                if dot(u(:,pp), u(:,pp-1)) < 0
                    u(:,pp) = -u(:,pp);
                end

            end

            u = unit(u);
            v = cross(fwd, u, 1);
        end

        
        
    end % methods
    
    
end
            
            
            
            