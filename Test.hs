{-# LANGUAGE DeriveGeneric, TypeFamilies #-}

module Main where

import Control.Arrow
import Control.Applicative
import GHC.Generics
import Graphics.Rendering.Ombra
import Graphics.Rendering.Ombra.Vector
import Utils.Play

data Vertex2D = Vertex2D Vec2 Vec3 deriving Generic
data GVertex2D = GVertex2D GVec2 GVec3 deriving Generic

instance MultiShaderType GVertex2D
instance ShaderInput GVertex2D
instance GeometryVertex GVertex2D where
        type Vertex GVertex2D = Vertex2D

tex :: Texture
tex = mkTexture 64 64 (potLinear True) [cols]
        where cols = [ visible (mod x 8 * 32) (mod y 8 * 32) 0
                     | x <- [0 .. 63], y <- [0 .. 63]
                     ]

tris :: Geometry GVertex2D
tris = mkGeometry [Triangle (Vertex2D (Vec2 0 0) (Vec3 1 0 0))
                            (Vertex2D (Vec2 0.5 0.5) (Vec3 0 1 0))
                            (Vertex2D (Vec2 0 0.5) (Vec3 0 0 1))]

render :: Float -> Draw GVec4 ()
render time = do draw $ image (vs ~~ time) fs tris
                 draw $ image vs' (fs' ~~ (time, tex)) tris
        where vs = sarr $ \(time, GVertex2D p c) -> 
                        ( (p ^+^ (GVec2 (sin time) (cos time / 8))) ^| 0 ^| 1
                        , c ^+^ GVec3 (abs $ cos (time / 8)) 0 0
                        )
              fs = sarr $ (^| 1)
              vs' = sarr $ \(GVertex2D p _) -> (2 *^ p ^| 0 ^| 1, p)
              fs' = sarr $ \((time, sampler), p) ->
                        sample sampler p ^+^ GVec4 0 0 (abs $ cos time) 0

main :: IO ()
main = animation render
