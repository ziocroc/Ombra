{-# LANGUAGE DataKinds, DeriveGeneric, GADTs #-}

-- |
-- Module:      Graphics.Rendering.Ombra.Shader.Default3D
-- License:     BSD3
-- Maintainer:  ziocroc@gmail.com
-- Stability:   experimental
-- Portability: GHC only

module Graphics.Rendering.Ombra.Shader.Default3D (
        Uniforms,
        Geometry3D,
        Texture2(..),
        Transform3(..),
        View3(..),
        Project3(..),
        Position3(..),
        UV(..),
        Normal3(..),
        vertexShader,
        fragmentShader
) where

import Graphics.Rendering.Ombra.Shader

type Uniforms = '[Project3, View3, Transform3, Texture2]

-- | A 3D geometry.
type Geometry3D = '[Position3, UV, Normal3]

-- | The texture that is applied to the object.
data Texture2 = Texture2 GSampler2D deriving Generic

-- | The matrix that transforms an object from model space to world space.
data Transform3 = Transform3 GMat4 deriving Generic

-- | World space -> view space.
data View3 = View3 GMat4 deriving Generic

-- | View space -> screen space.
data Project3 = Project3 GMat4 deriving Generic

-- | The position of the vertex.
data Position3 = Position3 GVec3 deriving Generic

-- | The vertex normal.
data Normal3 = Normal3 GVec3 deriving Generic

-- | The output position and normal are in view space.
vertexShader :: VertexShader '[ Project3, View3, Transform3 ]
                             Geometry3D
                             '[ Position3, UV, Normal3 ]
vertexShader (  Project3 projMatrix
             :- View3 viewMatrix
             :- Transform3 modelMatrix
             :- N)
             (Position3 pos :- uv :- Normal3 norm :- N) =
             let worldPos = modelMatrix .* (pos ^| 1.0)
                 viewPos = store $ viewMatrix .* worldPos
                 projPos = projMatrix .* viewPos
                 worldNorm = modelMatrix .* (norm ^| 0)
                 viewNorm = viewMatrix .* worldNorm
             in Vertex projPos :- Position3 (extract viewPos) :-
                uv :- Normal3 (extract viewNorm) :- N

fragmentShader :: FragmentShader '[ Texture2 ] [ Position3, UV, Normal3 ]
fragmentShader (Texture2 sampler :- N) (_ :- UV (GVec2 s t) :- _ :- N) =
        Fragment (texture2D sampler $ GVec2 s (1 - t)) :- N
