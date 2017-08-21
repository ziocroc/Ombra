{-# LANGUAGE MultiParamTypeClasses, ExistentialQuantification, ConstraintKinds,
             KindSignatures, DataKinds, GADTs, RankNTypes, FlexibleInstances,
             ScopedTypeVariables, TypeOperators, ImpredicativeTypes,
             TypeSynonymInstances, FlexibleContexts #-}

module Graphics.Rendering.Ombra.Shader.Program (
        MonadProgram(..),
        LoadedProgram(..),
        Program,
        ProgramIndex,
        program,
        setProgram,
        UniformLocation(..),
        programIndex
) where

import Data.Hashable
import qualified Data.HashMap.Strict as H
import Graphics.Rendering.Ombra.Shader
import Graphics.Rendering.Ombra.Shader.CPU
import Graphics.Rendering.Ombra.Shader.GLSL
import Graphics.Rendering.Ombra.Shader.Types
import Graphics.Rendering.Ombra.Internal.GL hiding (Program, UniformLocation)
import qualified Graphics.Rendering.Ombra.Internal.GL as GL
import Graphics.Rendering.Ombra.Internal.Resource
import Graphics.Rendering.Ombra.Internal.TList
import Unsafe.Coerce

data Program i o = Program (String, [(String, Int)]) String Int

data LoadedProgram = LoadedProgram !GL.Program (H.HashMap String Int) Int

newtype ProgramIndex = ProgramIndex Int deriving Eq

newtype UniformLocation = UniformLocation GL.UniformLocation

instance Hashable (Program i o) where
        hashWithSalt salt (Program _ _ h) = hashWithSalt salt h

instance Eq (Program i o) where
        (Program _ _ h) == (Program _ _ h') = h == h'

instance Hashable LoadedProgram where
        hashWithSalt salt (LoadedProgram _ _ h) = hashWithSalt salt h

instance Eq LoadedProgram where
        (LoadedProgram _ _ h) == (LoadedProgram _ _ h') = h == h'

instance GLES => Resource (Program g i) LoadedProgram GL where
        -- TODO: err check!
        loadResource i = loadProgram i
        unloadResource _ (LoadedProgram p _ _) = deleteProgram p

instance GLES => Resource (LoadedProgram, UniformID) UniformLocation GL where
        loadResource (LoadedProgram prg _ _, g) =
                do loc <- getUniformLocation prg . toGLString $ uniformName g
                   return . Right $ UniformLocation loc
        unloadResource _ _ = return ()

-- | Create a 'Program' from the shaders.
program :: (ShaderInput i, ShaderInput v, FragmentShaderOutput o)
        => VertexShader i (GVec4, v)
        -> FragmentShader v o
        -> Program i o
program vs fs = let (vss, (uid, attrs)) = compileVertexShader vs
                    fss = compileFragmentShader uid fs
                in Program (vss, attrs) fss (hash (vs, fs))

programIndex :: Program gs is -> ProgramIndex
programIndex (Program _ _ h) = ProgramIndex h

class (GLES, MonadGL m) => MonadProgram m where
        withProgram :: Program i o -> (LoadedProgram -> m ()) -> m ()
        getUniform :: UniformID -> m (Either String UniformLocation)

{-
setUniformValue :: (MonadProgram m, ShaderVar g, BaseUniform g)
                => proxy (s :: CPUSetterType *)
                -> g
                -> CPUBase g
                -> m ()
setUniformValue p g c = withUniforms p g c $ \n ug uc ->
        getUniform (uniformName g n) >>= \eu ->
                case eu of
                     Right (UniformLocation l) -> gl $ setUniform l ug uc
                     Left _ -> return ()
-}

setProgram :: MonadProgram m => Program i o -> m ()
setProgram p = withProgram p $ \(LoadedProgram glp _ _) -> gl $ useProgram glp

loadProgram :: GLES => Program g i -> GL (Either String LoadedProgram)
loadProgram (Program (vss, attrs) fss h) =
        do glp <- createProgram
  
           vs <- loadSource gl_VERTEX_SHADER vss
           fs <- loadSource gl_FRAGMENT_SHADER fss

           vsStatus <- getShaderParameterBool vs gl_COMPILE_STATUS
           fsStatus <- getShaderParameterBool fs gl_COMPILE_STATUS

           if isTrue vsStatus && isTrue fsStatus
           then do attachShader glp vs
                   attachShader glp fs
  
                   locs <- bindAttribs glp 0 attrs []
                   linkProgram glp

                   -- TODO: error check
  
                   -- TODO: ??
                   {-
                   detachShader glp vs
                   detachShader glp fs
                   -}
  
                   return . Right $ LoadedProgram glp
                                                  (H.fromList locs)
                                                  (hash glp)
           else do vsError <- shaderError vs vsStatus "Vertex shader"
                   fsError <- shaderError fs fsStatus "Fragment shader"

                   return . Left $ vsError ++ fsError

        where bindAttribs _ _ [] r = return r
              bindAttribs glp i ((nm, sz) : xs) r =
                        bindAttribLocation glp (fromIntegral i) (toGLString nm)
                        >> bindAttribs glp (i + sz) xs ((nm, i) : r)

              shaderError :: GLES => GL.Shader -> GLBool -> String -> GL String
              shaderError _ b _ | isTrue b = return ""
              shaderError s _ name = getShaderInfoLog s >>= \err ->
                        return $ name ++ " error:" ++ fromGLString err ++ "\n"

loadSource :: GLES => GLEnum -> String -> GL GL.Shader
loadSource ty src =
        do shader <- createShader ty
           shaderSource shader $ toGLString src
           compileShader shader
           return shader
