{-# LANGUAGE RankNTypes, ScopedTypeVariables, DataKinds, KindSignatures,
             TypeFamilies, FlexibleContexts, UndecidableInstances,
             FlexibleInstances, DefaultSignatures, TypeOperators #-}

{-|
Module:      Graphics.Rendering.Ombra.Shader
License:     BSD3
Maintainer:  ziocroc@gmail.com
Stability:   experimental
Portability: GHC only
-}

module Graphics.Rendering.Ombra.Shader (
        module Graphics.Rendering.Ombra.Shader.Language,
        ShaderStage(..),
        Shader,
        VertexShader,
        FragmentShader,
        -- * Uniforms
        uniform,
        (~~),
        -- * Optimized shaders
        UniformSetter,
        shader,
        shader1,
        uniform',
        (~*),
        sarr,
        -- * Fragment shader functionalities
        Fragment(..),
        farr,
        fragment,
        -- * Classes
        MultiShaderType(..),
        ShaderInput(..),
        FragmentShaderOutput(..),
        MapShader(..),
        Uniform(..)
) where

import Control.Arrow
import Control.Applicative
import Control.Category
import Data.Hashable
import Data.MemoTrie
import Data.Proxy
import GHC.Generics
import GHC.TypeLits
import Graphics.Rendering.Ombra.Internal.GL (Sampler2D)
import Graphics.Rendering.Ombra.Shader.Language
import qualified Graphics.Rendering.Ombra.Shader.Language.Functions as Shader
import Graphics.Rendering.Ombra.Shader.Language.Types
import Graphics.Rendering.Ombra.Shader.CPU
import Graphics.Rendering.Ombra.Shader.Types
import Graphics.Rendering.Ombra.Texture (Texture)
import Prelude hiding (id, (.))

newtype UniformSetter x = UniformSetter { unUniformSetter :: x }

instance Functor UniformSetter where
        fmap f (UniformSetter x) = UniformSetter $ f x

instance Applicative UniformSetter where
        pure = UniformSetter
        UniformSetter f <*> UniformSetter x = UniformSetter $ f x

instance Monad UniformSetter where
        return = pure
        UniformSetter x >>= f = f x

hashMST :: MultiShaderType a => a -> a
hashMST = mapMST (fromExpr . HashDummy . hash . toExpr)

-- | Create a shader function that can be reused efficiently.
shader :: (MultiShaderType i, MultiShaderType o) => Shader s i o -> Shader s i o
shader (Shader f hf) = Shader f (memoHash hf)
-- BUG: shader modifies the hash of the shader

-- | 'shader' with an additional parameter that can be used to set the values of
-- the uniforms.
shader1 :: (MultiShaderType i, MultiShaderType o)
        => (Shader s (UniformSetter x, i) o)
        -> (UniformSetter x -> Shader s i o)
shader1 (Shader f hf) = let err = "shader1: not an uniform value"
                            hf' = memoHash $ hf . second ((,) (error err))
                        in \x -> Shader (\(s, i) -> f (s, (x, i))) hf'

-- | @'shader' . 'arr'@
sarr :: (MultiShaderType i, MultiShaderType o) => (i -> o) -> Shader s i o
sarr = shader . arr

memoHash :: (MultiShaderType i, MultiShaderType o)
         => ((UniformID, i) -> (UniformID, o))
         -> ((UniformID, i) -> (UniformID, o))
memoHash hf = let mf = memo $ second hashMST . hf . second fromExprMST
              in mf . second toExprMST

-- | Add a shader variable that can be set with a CPU value.
uniform :: forall u s. Uniform u => Shader s (CPUUniform u) u
uniform = Shader (\(ShaderState uid umap tmap, multiValue) ->
                        let (uniExpr, uid') =
                                buildMST' (\t -> fromExpr . Uniform t) uid
                            acc value@(UniformValue _ _) (uid, umap, tmap) =
                                    (uid - 1, (uid, value) : umap, tmap)
                            acc value@(UniformTexture tex) (uid, umap, tmap) =
                                    (uid - 1, (uid, value) : umap, tex : tmap)
                            (_, umap', tmap') =
                                    foldrUniform (Proxy :: Proxy u) acc
                                                 (uid' - 1, umap, tmap)
                                                 multiValue
                        in (ShaderState uid' umap' tmap', uniExpr)
                 )
                 (\(uid, _) ->
                       let (uniExpr, uid') =
                               buildMST' (\t -> fromExpr . Uniform t) uid
                       in (uid', uniExpr)
                 )

-- | Like 'uniform' but uses a 'UniformSetter'.
uniform' :: Uniform u => Shader s (UniformSetter (CPUUniform u)) u
uniform' = unUniformSetter ^>> uniform

-- | Add a uniform and directly set it with the second operand.
infixl 9 ~~
(~~) :: Uniform u => Shader s (u, i) o -> CPUUniform u -> Shader s i o
shader ~~ u = (const u ^>> uniform) &&& id >>> shader

-- | Add a uniform and directly set it with a 'UniformSetter'.
infixl 9 ~*
(~*) :: Uniform u
     => Shader s (u, i) o
     -> UniformSetter (CPUUniform u)
     -> Shader s i o
shader ~* u = (const u ^>> uniform') &&& id >>> shader

-- | This works like 'sarr' but provides a 'Fragment'.
farr :: (MultiShaderType i, MultiShaderType o)
     => (Fragment -> i -> o)
     -> FragmentShader i o
farr f = shader $ arr (f frag)

fragment :: FragmentShader a Fragment
fragment = arr $ const frag

frag :: Fragment
frag = Fragment { fragCoord = Shader.fragCoord
                , fragFrontFacing = Shader.fragFrontFacing
                , dFdx = Shader.dFdx
                , dFdy = Shader.dFdy
                , fwidth = Shader.fwidth
                }
