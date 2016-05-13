{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE Rank2Types            #-}
{-# LANGUAGE TypeFamilies          #-}

-- | IO-based implementation of MonadTimed type class.

module RSCoin.Timed.TimedIO
       ( TimedIO
       , runTimedIO
       , runTimedIO_
       ) where

import qualified Control.Concurrent          as C
import           Control.Monad               (void)
import           Control.Monad.Base          (MonadBase)
import           Control.Monad.Catch         (MonadCatch, MonadThrow, MonadMask,
                                              throwM)
import           Control.Monad.Loops         (whileM)
import           Control.Monad.Reader        (ReaderT (..), ask, runReaderT)
import           Control.Monad.Trans         (MonadIO, lift, liftIO)
import           Control.Monad.Trans.Control (MonadBaseControl, StM,
                                              liftBaseWith, restoreM)
import           Data.IORef                  (newIORef, readIORef, writeIORef)
import           Data.Time.Clock.POSIX       (getPOSIXTime)
import qualified System.Timeout              as T

import           RSCoin.Timed.MonadTimed     (Microsecond, MonadTimed (..),
                                              MonadTimedError (MTTimeoutError))

newtype TimedIO a = TimedIO
    { getTimedIO :: ReaderT Microsecond IO a
    } deriving (Functor, Applicative, Monad, MonadIO, MonadThrow, MonadCatch
               , MonadBase IO, MonadMask)

instance MonadBaseControl IO TimedIO where
    type StM TimedIO a = a

    liftBaseWith f = TimedIO $ liftBaseWith $ \g -> f $ g . getTimedIO

    restoreM = TimedIO . restoreM

instance MonadTimed TimedIO where
    localTime = TimedIO $ (-) <$> lift curTime <*> ask

    wait relativeToNow = do
        cur <- localTime
        liftIO $ C.threadDelay $ fromIntegral $ relativeToNow cur

    fork (TimedIO a) = TimedIO $ lift . forkIO . runReaderT a =<< ask
    
    myThreadId = C.myThreadId
    
    killThread = C.killThread

    timeout t (TimedIO action) = TimedIO $ do
        res <- liftIO . T.timeout (fromIntegral t) . runReaderT action =<< ask
        maybe (throwM $ MTTimeoutError "Timeout has exceeded") return res

-- | Launches this timed action
runTimedIO :: TimedIO a -> IO a
runTimedIO = (curTime >>= ) . runReaderT . getTimedIO

-- | Launches this timed action, ignoring the result
runTimedIO_ ::  TimedIO a -> IO ()
runTimedIO_ = void . runTimedIO

curTime :: IO Microsecond
curTime = round . ( * 1000000) <$> getPOSIXTime
