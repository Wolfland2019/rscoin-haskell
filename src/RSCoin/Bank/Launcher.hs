{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TupleSections    #-}

-- | Convenience functions to launch bank or do high-level operations
-- with it.

module RSCoin.Bank.Launcher
       ( launchBankReal
       , launchBank
       , addMintetteInPlace
       , addExplorerInPlace
       , addMintetteReq
       , addExplorerReq
       , removeMintetteReq
       , removeExplorerReq
       ) where

import           Control.Monad             (when)
import           Control.Monad.Catch       (bracket, throwM)
import           Control.Monad.Trans       (liftIO)
import           Data.Acid.Advanced        (update')
import           Data.IORef                (newIORef)
import           Data.Maybe                (fromJust, isNothing)
import           Data.Time.Units           (TimeUnit)

import           Formatting                (int, sformat, (%))

import           RSCoin.Core               (Explorer, Mintette, PeriodId,
                                            PublicKey, SecretKey, sign)
import           RSCoin.Core.Communication (getBlockchainHeight,
                                            getMintettePeriod,
                                            sendBankLocalControlRequest)
import qualified RSCoin.Core.Protocol      as P (BankLocalControlRequest (..))
import           RSCoin.Timed              (MsgPackRpc, WorkMode, fork, fork_,
                                            killThread, runRealModeBank)

import           RSCoin.Bank.AcidState     (AddExplorer (AddExplorer),
                                            AddMintette (AddMintette), State,
                                            closeState, openState)
import           RSCoin.Bank.Error         (BankError (BEInconsistentResponse))
import           RSCoin.Bank.Server        (serve)
import           RSCoin.Bank.Worker        (runExplorerWorker,
                                            runWorkerWithPeriod)

bankWrapperReal :: SecretKey
                -> FilePath
                -> Maybe FilePath
                -> (State -> MsgPackRpc a)
                -> IO a
bankWrapperReal bankSk storagePath confPath =
    runRealModeBank confPath bankSk .
    bracket (liftIO $ openState storagePath) (liftIO . closeState)

-- | Launch Bank in real mode. This function works indefinitely.
launchBankReal
    :: (TimeUnit t)
    => t -> FilePath -> Maybe FilePath -> SecretKey -> IO ()
launchBankReal periodDelta storagePath confPath bankSk =
    bankWrapperReal bankSk storagePath confPath $
    launchBank periodDelta bankSk storagePath

-- | Launch Bank in any WorkMode. This function works indefinitely.
launchBank
    :: (TimeUnit t, WorkMode m)
    => t -> SecretKey -> FilePath -> State -> m ()
launchBank periodDelta bankSk storagePath st = do
    mainIsBusy <- liftIO $ newIORef False
    let startWorker =
            runWorkerWithPeriod
                periodDelta
                mainIsBusy
                bankSk
                st
                (Just storagePath)
        restartWorker tId = killThread tId >> fork startWorker
    workerThread <- fork startWorker
    fork_ $ runExplorerWorker periodDelta mainIsBusy bankSk st
    serve st workerThread restartWorker

-- | Adds mintette directly into bank's state
addMintetteInPlace :: Maybe FilePath
                   -> SecretKey
                   -> FilePath
                   -> Mintette
                   -> PublicKey
                   -> IO ()
addMintetteInPlace confPath bankSk storagePath m k =
    bankWrapperReal bankSk storagePath confPath $
    flip update' (AddMintette m k)

-- | Add explorer to Bank inside IO Monad.
addExplorerInPlace :: Maybe FilePath
                   -> SecretKey
                   -> FilePath
                   -> Explorer
                   -> PeriodId
                   -> IO ()
addExplorerInPlace confPath bankSk storagePath e pId =
    bankWrapperReal bankSk storagePath confPath $
    flip update' (AddExplorer e pId)

-- | Add mintette to Bank (send a request signed with bank's sk)
-- Also pings minttete to check that it's compatible
addMintetteReq :: Maybe FilePath -> SecretKey -> Mintette -> PublicKey -> IO ()
addMintetteReq confPath bankSk m k = do
    let proof = sign bankSk (m, k)
    runRealModeBank confPath bankSk $ do
        bankPid <- getBlockchainHeight
        mintettePid <- getMintettePeriod m
        when (isNothing mintettePid) $
            throwM $ BEInconsistentResponse
            "Mintette didn't respond on ping request."
        let mPid = fromJust mintettePid
        when (mPid /= (-1) && mPid > bankPid) $
            throwM $ BEInconsistentResponse $
            sformat ("Mintette had period id " % int %
                     " while bank's is " % int %
                     ". Check out, maybe mintette's state" %
                     " is old & incosistent.")
            mPid bankPid
        sendBankLocalControlRequest $ P.AddMintette m k proof

-- | Add explorer to Bank inside IO Monad.
addExplorerReq :: Maybe FilePath -> SecretKey -> Explorer -> PeriodId -> IO ()
addExplorerReq confPath bankSk e pId = do
    let proof = sign bankSk (e, pId)
    runRealModeBank confPath bankSk $
        sendBankLocalControlRequest $ P.AddExplorer e pId proof

-- | Sends a request to remove mintette
removeMintetteReq :: Maybe FilePath -> SecretKey -> String -> Int -> IO ()
removeMintetteReq confPath bankSk mintetteHost mintettePort = do
    let proof = sign bankSk (mintetteHost, mintettePort)
    runRealModeBank confPath bankSk $
        sendBankLocalControlRequest $
        P.RemoveMintette mintetteHost mintettePort proof

-- | Sends a request to remove explorer
removeExplorerReq :: Maybe FilePath -> SecretKey -> String -> Int -> IO ()
removeExplorerReq confPath bankSk mintetteHost mintettePort = do
    let proof = sign bankSk (mintetteHost, mintettePort)
    runRealModeBank confPath bankSk $
        sendBankLocalControlRequest $
        P.RemoveExplorer mintetteHost mintettePort proof
