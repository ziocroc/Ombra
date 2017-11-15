{-# LANGUAGE GADTs, DataKinds, MultiParamTypeClasses #-}

module Graphics.Rendering.Ombra.Image.Types where

import Data.Foldable
import Data.Semigroup
import Control.Arrow
import Graphics.Rendering.Ombra.Geometry.Types
import Graphics.Rendering.Ombra.Shader

data Image o where
       Image :: ( ShaderInput i
                , ShaderInput v
                , Foldable t
                , GeometryVertex i
                , ElementType e)
             => t (Geometry e i, vu, fu)
             -> (UniformSetter vu -> VertexShader i (GVec4, v))
             -> (UniformSetter fu -> FragmentShader v o)
             -> Image o
       SeqImage :: Image o -> Image o -> Image o
       NoImage :: Image o

instance Functor Image where
        fmap f (Image g vs fs) = Image g vs (\fu -> fs fu >>^ f)
        fmap f (SeqImage i i') = SeqImage (fmap f i) (fmap f i')
        fmap _ NoImage = NoImage

instance MapShader Image FragmentShaderStage where
        mapShader f (Image g vs fs) = Image g vs (\fu -> fs fu >>> f)
        mapShader f (SeqImage i i') = SeqImage (mapShader f i) (mapShader f i')
        mapShader _ NoImage = NoImage

instance Semigroup (Image o) where
        (<>) = SeqImage

instance Monoid (Image o) where
        mappend = (<>)
        mempty = NoImage