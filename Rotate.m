% Rotate  Matrix transformation for geometry
% 
% Example constructor:
%
% r = Rotate(@(p) [cos(p) -sin(p) 0; sin(p) cos(p) 0; 0 0 1], childMeshes);
%
classdef Rotate < dmodel.Node
    
    properties
        children = {};
        matrix = @(p) eye(3);
    end
    
    methods
        function obj = Rotate(matrix, varargin)
            if nargin > 0
                obj.matrix = matrix;
                obj.children = varargin;
            end
        end
        
        function m = meshes(obj, varargin)
            import dmodel.*
            
            if nargin > 1
                params = varargin{1};
            else
                params = [];
            end
            
            m = {};
            
            myMatrix = obj.matrix(params);
            if det(myMatrix) <= 0
                error('Rotation matrix has nonpositive determinant');
            end
            
            for cc = 1:length(obj.children)
                childMeshes = obj.children{cc}.meshes(params);
                for mm = 1:length(childMeshes)
                    v0 = childMeshes{mm}.vertices;
                    jac0 = childMeshes{mm}.jacobian;
                    
                    %numVerts = length(v0)/3;
                    
                    myVertices = blockProduct(...
                        obj.matrix(params), v0, [3 3], [3 1]);
                    
                    if ~isempty(params)
                        myJacobian = ...
                            blockProduct(obj.matrix(params), ...
                                jac0, [3 3], [3 1]) + ...
                            blockProduct(jacobian(obj.matrix, params), ...
                                v0, [3 3], [3 1]);
                    else
                        myJacobian = sparse(length(v0), 0);
                    end
                    
                    m{end+1} = Mesh(myVertices,...
                        childMeshes{mm}.faces,...
                        myJacobian);%, ...
                       % childMeshes{mm}.permittivity,...
                       % childMeshes{mm}.permeability);
                end
            end
        end
        
    end
    
end