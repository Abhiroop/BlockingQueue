{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ExistentialQuantification #-}
module BlockingQueue where

import Data.Typeable
import GHC.Generics
import Data.Binary
import Data.List
import Control.Distributed.Process.Async
import Control.Distributed.Process hiding (call)
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node
import Control.Distributed.Process.ManagedProcess hiding (enqueue, dequeue)
import Control.Distributed.Process.Extras.Time
import Control.Distributed.Process.Serializable
import Control.Distributed.Process.Extras.Internal.Types
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Data.Sequence hiding (length)
--import Prelude hiding (length)

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
  } deriving (Typeable)

enqueue :: Seq a -> a -> Seq a
enqueue s a = a <| s

dequeue :: Seq a -> Maybe (a, Seq a)
dequeue s = maybe Nothing (\(s' :> a) -> Just (a, s')) $ getR s

getR :: Seq a -> Maybe (ViewR a)
getR s =
  case (viewr s) of
    EmptyR -> Nothing
    a      -> Just a

acceptTask :: Serializable a
           => BlockingQueue a
           -> CallRef (Either ExitReason a)
           -> Closure (Process a)
           -> Process (BlockingQueue a)
acceptTask s@(BlockingQueue sz' runQueue taskQueue) from task' =
  let currentSz = length runQueue
  in case currentSz >= sz' of
       True -> do
         return $ s {accepted = enqueue taskQueue (from,task')}
       False -> do
         proc <- unClosure task'
         asyncHandle <- (async . task) proc
         ref <- monitorAsync asyncHandle
         let taskEntry = (ref, from, asyncHandle)
         return s { active = (taskEntry:runQueue) }

storeTask :: Serializable a
          => BlockingQueue a
          -> CallRef (Either ExitReason a)
          -> Closure (Process a)
          -> Process (ProcessReply (Either ExitReason a) (BlockingQueue a))
storeTask s r c = acceptTask s r c >>= noReply_ --because we are deferring our reply

{-
1. find the async handle for our monitor ref
2. obtain the result using the handle
3. send the result to the client
4. bump another task from the backlog (if there is one)
-}

findWorker :: MonitorRef
           -> [(MonitorRef, CallRef (Either ExitReason a), Async a)]
           -> Maybe (MonitorRef, CallRef (Either ExitReason a), Async a)
findWorker key = find (\(ref,_,_) -> ref == key)

deleteFromRunQueue :: (MonitorRef, CallRef (Either ExitReason a), Async a)
                   -> [(MonitorRef, CallRef (Either ExitReason a), Async a)]
                   -> [(MonitorRef, CallRef (Either ExitReason a), Async a)]
deleteFromRunQueue c@(p, _, _) runQ = deleteBy (\_ (b, _, _) -> b == p) c runQ


taskComplete :: forall a . Serializable a
             => BlockingQueue a
             -> ProcessMonitorNotification
             -> Process (ProcessAction (BlockingQueue a))
taskComplete s@(BlockingQueue _ runQ _)
             (ProcessMonitorNotification ref _ _) =
  let worker = findWorker ref runQ in
  case worker of
    Just t@(_, c, h) -> wait h >>= respond c >> bump s t >>= continue
    Nothing          -> continue s

  where
    respond :: CallRef (Either ExitReason a)
            -> AsyncResult a
            -> Process ()
    respond c (AsyncDone       r) = replyTo c ((Right r) :: (Either ExitReason a))
    respond c (AsyncFailed     d) = replyTo c ((Left (ExitOther $ show d))  :: (Either ExitReason a))
    respond c (AsyncLinkFailed d) = replyTo c ((Left (ExitOther $ show d))  :: (Either ExitReason a))
    respond _      _              = die $ ExitOther "IllegalState"

    bump :: BlockingQueue a
         -> (MonitorRef, CallRef (Either ExitReason a), Async a)
         -> Process (BlockingQueue a)
    bump st@(BlockingQueue _ runQueue acc) worker =
      let runQ2 = deleteFromRunQueue worker runQueue
          accQ  = dequeue acc
      in case accQ of
           Nothing            -> return st { active = runQ2 }
           Just ((tr,tc), ts) -> acceptTask (st { accepted = ts, active = runQ2 }) tr tc
