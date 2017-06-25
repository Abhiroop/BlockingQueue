{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE DeriveGeneric #-}
module BlockingQueue where

import Data.Typeable
import GHC.Generics
import Data.Binary
import Control.Distributed.Process hiding (call)
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node
import Control.Distributed.Process.ManagedProcess
import Control.Distributed.Process.Extras.Time
import Control.Distributed.Process.Serializable
import Control.Distributed.Process.Extras.Internal.Types
import Network.Transport.TCP (createTransport, defaultTCPParameters)

executeTask :: forall s a . (Addressable s, Serializable a)
            => s
            -> Closure (Process a)
            -> Process (Either String a)
executeTask = undefined
