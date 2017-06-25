{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE DeriveGeneric #-}
module BlockingQueue where

import Data.Typeable
import GHC.Generics
import Data.Binary
import Control.Distributed.Process.Async
import Control.Distributed.Process hiding (call)
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node
import Control.Distributed.Process.ManagedProcess
import Control.Distributed.Process.Extras.Time
import Control.Distributed.Process.Serializable
import Control.Distributed.Process.Extras.Internal.Types
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Data.Sequence

executeTask :: forall s a . (Addressable s, Serializable a)
            => s
            -> Closure (Process a)
            -> Process (Either String a)
executeTask = call

type SizeLimit = Int

data BlockingQueue a = BlockingQueue {
  poolSize :: SizeLimit ,
  active :: [(MonitorRef, CallRef (Either ExitReason a), Async a)] ,
  accepted :: Seq (CallRef (Either ExitReason a), Closure (Process a))
  }
