{-# LANGUAGE ExistentialQuantification, TupleSections, TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wall #-}

-- {-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP
-- {-# OPTIONS_GHC -fno-warn-unused-binds   #-} -- TEMP

----------------------------------------------------------------------
-- |
-- Module      :  Circat.Mealy
-- Copyright   :  (c) 2014 Tabula, Inc.
-- 
-- Maintainer  :  conal@tabula.com
-- Stability   :  experimental
-- 
-- Mealy machines
----------------------------------------------------------------------

module Circat.Mealy where

-- TODO: explicit exports

import Prelude hiding (id,(.))

import Circat.Misc ((:*),(:+))
import Circat.Category

data Mealy a b = forall s. Mealy ((s,a) -> (s,b)) s

counter :: Mealy () Int
counter = Mealy (\ (n,()) -> (n+1,n)) 0

instance Category Mealy where
  id = Mealy id ()
  Mealy g t0 . Mealy f s0 = Mealy h (s0,t0)
   where
     h ((s,t),a) = ((s',t'),c)
      where
        (s',b) = f (s,a)
        (t',c) = g (t,b)

arr :: (a -> b) -> Mealy a b
arr f = Mealy (second f) ()

instance ProductCat Mealy where
  exl = arr exl
  exr = arr exr
  Mealy f s0 *** Mealy g t0 = Mealy h (s0,t0)
   where
     h = transP2 . (f *** g) . transP2

--   Mealy f s0 *** Mealy g t0 = Mealy h (s0,t0)
--    where
--      h ((s,t),(a,b)) = ((s',t'),(c,d))
--       where
--         (s',c) = f (s,a)
--         (t',d) = g (t,b)

transP2 :: ((p :* q) :* (r :* s)) -> ((p :* r) :* (q :* s))
transP2 ((p,q),(r,s)) = ((p,r),(q,s))

-- TODO: Rewritten with just categorical vocabulary

transP2' :: ((p :* q) :* (r :* s)) -> ((p :* r) :* (q :* s))
transP2' = (exl.exl &&& exl.exr) &&& (exr.exl &&& exr.exr)

instance CoproductCat Mealy where
  inl = arr inl
  inr = arr inr

--   Mealy f s0 ||| Mealy g t0 = Mealy h (s0,t0)
--    where
--      h ((s,t),Left  a) = first (,t) (f (s,a))
--      h ((s,t),Right b) = first (s,) (g (t,b))

--   Mealy f s0 ||| Mealy g t0 = Mealy h (s0,t0)
--    where
--      h ((s,t),Left  a) = ((s',t), c) where (s',c) = f (s,a)
--      h ((s,t),Right b) = ((s,t'), c) where (t',c) = g (t,b)

  Mealy f s0 +++ Mealy g t0 = Mealy h (s0,t0)
   where
     h ((s,t),Left  a) = ((s',t), Left  c) where (s',c) = f (s,a)
     h ((s,t),Right b) = ((s,t'), Right d) where (t',d) = g (t,b)

--   Mealy f s0 +++ Mealy g t0 = Mealy h (s0,t0)
--    where
--      h = transS2 . (f +++ g) . transS2

transS2 :: ((p :+ q) :+ (r :+ s)) -> ((p :+ r) :+ (q :+ s))
transS2 (Left  (Left  p)) = Left  (Left  p)
transS2 (Left  (Right q)) = Right (Left  q)
transS2 (Right (Left  r)) = Left  (Right r)
transS2 (Right (Right s)) = Right (Right s)

-- TODO: Rewritten with just categorical vocabulary

transS2' :: ((p :+ q) :+ (r :+ s)) -> ((p :+ r) :+ (q :+ s))
transS2' = (inl.inl ||| inr.inl) ||| (inl.inr ||| inr.inr)

instance ClosedCat Mealy where
  apply = arr apply
  curry (Mealy (f :: (s,(a,b)) -> (s,c)) s0) = Mealy g s0
   where
     g :: (s,a) -> (s,b -> c)
     g (s,a) = _


f :: (s,(a,b)) -> (s,c)
curry f :: s -> (a,b) -> (s,c)
curry . curry f :: s -> a -> b -> (s,c)
uncurry (curry . curry f) :: (s,a) -> b -> (s,c)
need :: (s,a) -> (s,b -> c)
