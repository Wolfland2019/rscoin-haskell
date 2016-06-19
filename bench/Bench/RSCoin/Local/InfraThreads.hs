module Bench.RSCoin.Local.InfraThreads
        ( addMintette
        , bankThread
        , mintetteThread
        ) where

import           Control.Monad.Catch        (bracket)
import           Control.Monad.Trans        (liftIO)
import           Data.String                (IsString)
import           Data.Time.Units            (TimeUnit)
import           System.FilePath            ((</>))

import qualified RSCoin.Bank                as B
import           RSCoin.Core                (Mintette (Mintette), PublicKey,
                                             SecretKey, bankSecretKey,
                                             defaultPort)
import qualified RSCoin.Mintette            as M
import           RSCoin.Timed               (fork, runRealModeLocal)

import           Bench.RSCoin.FilePathUtils (dbFormatPath)

localhost :: IsString s => s
localhost = "127.0.0.1"

bankDir :: FilePath -> FilePath
bankDir = (</> "bank-db")

addMintette :: Int -> FilePath -> PublicKey -> IO ()
addMintette mintetteId benchDir = B.addMintetteIO (bankDir benchDir) mintette
  where
    mintette = Mintette localhost (defaultPort + mintetteId)

bankThread :: (TimeUnit t) => t -> FilePath -> IO ()
bankThread periodDelta benchDir
    = B.launchBank periodDelta (benchDir </> "bank-db") bankSecretKey

mintetteThread :: Int -> FilePath -> SecretKey -> IO ()
mintetteThread mintetteId benchDir secretKey =
    runRealModeLocal $
    bracket
        (liftIO $
         M.openState $ benchDir </> dbFormatPath "mintette-db" mintetteId)
        (liftIO . M.closeState) $
    \mintetteState ->
         do _ <- fork $ M.runWorker secretKey mintetteState
            M.serve (defaultPort + mintetteId) mintetteState secretKey