{-# LANGUAGE CPP, DataKinds #-}

#ifdef __GHCJS__
{-# LANGUAGE OverloadedStrings, JavaScriptFFI, InterruptibleFFI #-}
#endif

module Utils.Play (
        play,
        animation,
        static
) where

import Graphics.Rendering.Ombra
import qualified Graphics.Rendering.Ombra.D2 as D2
import Graphics.Rendering.Ombra.Draw
import Control.Monad.IO.Class
import Data.Hashable
import Data.IORef
import System.Exit (exitFailure)

import Utils.Input

#ifdef __GHCJS__

import Data.String
import Graphics.Rendering.Ombra.Backend.WebGL
import GHCJS.Foreign.Callback
import GHCJS.Types
import JavaScript.TypedArray
import JavaScript.TypedArray.Internal
import JavaScript.TypedArray.DataView
import System.Mem (performGC)

foreign import javascript unsafe "document.querySelector($1)"
        query :: JSString -> IO JSVal

foreign import javascript unsafe "$1.width" getWidth :: JSVal -> IO Int
foreign import javascript unsafe "$1.height" getHeight :: JSVal -> IO Int

foreign import javascript unsafe "$1.data" imgData :: JSVal -> IO Uint8Array

foreign import javascript interruptible "window.requestAnimationFrame($c);"
        waitFrame :: IO Double

foreign import javascript unsafe "alert" alert :: JSString -> IO ()

foreign import javascript unsafe "$1.addEventListener($2, $3)"
        addEventListener :: JSVal -> JSString -> Callback (JSVal -> IO ()) -> IO ()
foreign import javascript unsafe "$1.clientX" clientX :: JSVal -> IO Int
foreign import javascript unsafe "$1.clientY" clientY :: JSVal -> IO Int

play :: MonadIO m
     => Int
     -> Int
     -> Bool
     -> Draw ()
     -> (Float -> (Int, Int) -> m (Draw ()))
     -> (InputEvent -> IO ())
     -> ((Int, Int) -> IO ())
     -> m ()
play width height requireBuffers initialization frame inpCallback _ =
        do canvas <- liftIO $ query "canvas"
           ctx <- liftIO $ makeContext canvas
           width <- liftIO $ getWidth canvas
           height <- liftIO $ getHeight canvas
           inpCtl <- liftIO $ mkInputControl canvas inpCallback

           mextError <- liftIO $ checkExtensions requireBuffers ctx
           case mextError of
                Just extError -> liftIO $ alert (fromString extError) >>
                                          exitFailure
                Nothing -> return ()
           stateRef <- liftIO $ drawState width height >>= newIORef

           let liftDraw = liftIO . flip (refDrawCtx ctx) stateRef
           liftDraw $ drawInit >> initialization
           loop $ \t -> do draw <- frame (realToFrac t) (width, height)
                           liftDraw $ do clearBuffers [ColorBuffer, DepthBuffer]
                           liftDraw draw
                           liftIO $ performGC

           return ()
        where loop a = do t <- liftIO waitFrame
                          a $ t / 1000
                          loop a


#else

import Control.Concurrent
import Data.Time.Clock
import Graphics.Rendering.Ombra.Backend.OpenGL
import Graphics.UI.GLFW as G
import System.Mem (performMinorGC)

play :: MonadIO m
     => Int
     -> Int
     -> Bool
     -> Draw ()
     -> (Float -> (Int, Int) -> m (Draw ()))
     -> (InputEvent -> IO ())
     -> ((Int, Int) -> IO ())
     -> m ()
play width height requireBuffers initialization frame inpCallback sizeCallback =
        do w <- liftIO $ initWindow
           stateRef <- liftIO $ drawState width height >>= newIORef
           ctx <- liftIO $ makeContext
           t0 <- liftIO $ getCurrentTime
           inpCtl <- liftIO $ mkInputControl w inpCallback

           mextError <- liftIO $ checkExtensions requireBuffers ctx
           case mextError of
                Just extError -> liftIO $ putStrLn extError >> exitFailure
                Nothing -> return ()

           let liftDraw = liftIO . flip (refDrawCtx ctx) stateRef
           liftDraw $ drawInit >> initialization

           liftIO . setWindowSizeCallback w . Just $ \_ width' height' ->
                   flip (refDrawCtx ctx) stateRef $
                           do resizeViewport width' height'
                              liftIO $ sizeCallback (width', height')

           loop t0 $ \t -> do (width', height') <- liftIO $ getWindowSize w
                              draw <- frame t (width', height')
                              liftDraw $ clearBuffers [ColorBuffer, DepthBuffer]
                              liftDraw draw
                              liftIO $ do performMinorGC
                                          swapBuffers w
           return ()
        where loop t0 a = do t <- liftIO $ getCurrentTime
                             a . realToFrac $ diffUTCTime t t0
                             tf <- liftIO $ getCurrentTime
                             let diff = realToFrac $ diffUTCTime tf t
                                 delaySec = max 0 $ maxDelay - diff
                                 delay = floor $ delaySec * 1000000
                             liftIO pollEvents
                             liftIO . threadDelay $ delay
                             loop t0 a

              maxDelay = 0.03 :: Float

              initWindow = do G.init
                              windowHint $ WindowHint'ClientAPI ClientAPI'OpenGL
                              windowHint $ WindowHint'ContextVersionMajor 2
                              windowHint $ WindowHint'ContextVersionMinor 1
                              windowHint $ WindowHint'StencilBits 8
                              Just w <- createWindow width height ""
                                                     Nothing Nothing
                              makeContextCurrent $ Just w
                              return w
#endif

checkExtensions :: GLES => Bool -> Ctx -> IO (Maybe String)
checkExtensions requireBuffers ctx =
        do vaoExt <- hasVertexArrayObjects ctx
           floatTexExt <- hasFloatTextures ctx
           drawBufsExt <- hasDrawBuffers ctx

           let e1 = [ "\nVertex array objects are not supported." | not vaoExt ]
               e2 = [ "\nFloat textures are not supported."
                    | requireBuffers && not floatTexExt ]
               e3 = [ "\nMRT are not supported."
                    | requireBuffers && not drawBufsExt ]
           
           return $ case concat [e1, e2, e3] of
                         [] -> Nothing
                         errs -> Just $ "ERROR:" ++ concat errs

animation :: (Float -> Layer) -> IO ()
animation f = play 512 512
                   False
                   (return ())
                   (\t _ -> return $ drawLayer (f t))
                   (const (return ()))
                   (const (return ()))

static :: Layer -> IO ()
static = animation . const
