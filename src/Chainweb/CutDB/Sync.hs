{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- |
-- Module: Chainweb.CutDB.Sync
-- Copyright: Copyright © 2018 Kadena LLC.
-- License: MIT
-- Maintainer: Lars Kuhtz <lars@kadena.io>
-- Stability: experimental
--
-- P2P session for synchronizing the current cut with the the peers in the P2P
-- network.
--
module Chainweb.CutDB.Sync
( syncSession
) where

import Control.Concurrent.Async
import Control.Exception
import Control.Lens (set, view)
import Control.Monad

import qualified Data.Text as T
import qualified Data.Text.Encoding as T

import GHC.Generics

import Web.DeepRoute.Client

import qualified Streaming.Prelude as S

import System.LogLevel

-- internal modules

import Chainweb.BlockHeight
import Chainweb.Cut (_cutHeight, cutMap)
import Chainweb.Cut.CutHashes
import Chainweb.CutDB
import Chainweb.CutDB.RestAPI
import Chainweb.CutDB.RestAPI.Client
import Chainweb.Utils
import Chainweb.Version

import P2P.Peer
import P2P.Session hiding (ClientEnv)

-- -------------------------------------------------------------------------- --
-- Client Env

data CutClientEnv = CutClientEnv
    { _envChainwebVersion :: !ChainwebVersion
    , _envClientEnv :: !ClientEnv
    }
    deriving (Generic)

putCut
    :: CutClientEnv
    -> CutHashes
    -> IO ()
putCut (CutClientEnv v env) ch =
    newCutPutClient (RootedClientEnv (T.encodeUtf8 $ "chainweb/0.0/" <> toText v <> "/cut") env) ch

getCut
    :: CutClientEnv
    -> CutHeight
    -> IO CutHashes
getCut (CutClientEnv v env) h =
    newCutGetClient (RootedClientEnv (T.encodeUtf8 $ "chainweb/0.0/" <> toText v <> "/cut") env) Nothing

-- -------------------------------------------------------------------------- --
-- Sync Session

catchupStepSize :: CutHeight
catchupStepSize = 1000

syncSession
    :: ChainwebVersion
    -> PeerInfo
    -> CutDb tbl
    -> P2pSession
syncSession v p db logg env pinf = do
    race_
        (S.mapM_ send $ S.map (cutToCutHashes (Just p)) $ cutStream db)
        (forever $ receive >> approximateThreadDelay 2000000 {- 2 seconds -})
            -- Usually we rely on blocks being pushed to us, but every 2
            -- seconds we pull.

            -- FIXME make this configurable or dynamic
            -- FIXME use Etag along with if-non-match precondition.

    -- this code must not be reached
    logg @T.Text Error "unexpectedly exited cut sync session"
    return False
  where
    cenv = CutClientEnv v env

    send c = do
        putCut cenv c
        logg @T.Text Debug $ "put cut " <> encodeToText c

    receive = do
        cur <- _cut db

        -- Query cut that is at most 'catchupStepSize' blocks ahead
        let curHeight = _cutHeight cur
            curChainCount = length $ view cutMap cur
            limit = curHeight + min catchupStepSize (int farAheadThreshold * int curChainCount - 1)
                -- Cf. documentation of 'farAheadThreshold' for why this bound
                -- is needed. Note that 'farAheadThreshold' is of type
                -- 'BlockHeight'. So we multiply it with the (current) number
                -- chains to get an upper bound on the cut height.

        c <- getCut cenv limit

        let c' = set cutOrigin (Just pinf) c
        logg @T.Text Debug $ "received cut " <> encodeToText c'
        addCutHashes db c'
