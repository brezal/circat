{-# LANGUAGE GADTs, FlexibleInstances, FlexibleContexts, Rank2Types #-}
{-# LANGUAGE TypeFamilies #-}
{-# OPTIONS_GHC -Wall #-}

-- {-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP
-- {-# OPTIONS_GHC -fno-warn-unused-binds   #-} -- TEMP

----------------------------------------------------------------------
-- |
-- Module      :  Circat.Scan
-- Copyright   :  (c) 2014 Tabula, Inc.
-- 
-- Maintainer  :  conal@tabula.com
-- Stability   :  experimental
-- 
-- Parallel scan
----------------------------------------------------------------------

module Circat.Scan
  ( Zippable(..), zipWith
  , LScanTy, LScan(..), lscanInc
  , lsums, lproducts, lsums', lproducts'
  , shiftL, shiftR
  , lscanProd, lscanProd', lscanComp, lscanComp'
  ) where

import Prelude hiding (zip,unzip,zipWith)

import Data.Monoid (Monoid(..),(<>),Sum(..),Product(..))
import Data.Functor ((<$>))
import Control.Arrow ((***))
import Data.Traversable (Traversable(..)) -- ,mapAccumR
import Control.Applicative (Applicative(..))

import Circat.Misc (Unop)
import Circat.Rep

type LScanTy f = forall a. Monoid a => f a -> (f a, a)

class Functor f => LScan f where
  lscan :: LScanTy f
  -- Temporary hack to avoid newtype-like representation.
  lscanDummy :: f a
  lscanDummy = undefined

-- | Scan a product of functors. See also 'lscanProd'.
lscanProd' :: (Functor g, Monoid a)
           => LScanTy f -> LScanTy g
           -> (f a, g a) -> ((f a, g a), a)
lscanProd' lscanF lscanG (fa,ga) = ((fa', adjust <$> ga'), adjust gx)
 where
   (fa',fx) = lscanF fa
   (ga',gx) = lscanG ga
   adjust   = (fx <>)

-- | Scan a product of functors. See also 'lscanProd''.
lscanProd :: (Functor g, Monoid a, LScan f, LScan g)
          => (f a, g a) -> ((f a, g a), a)
lscanProd = lscanProd' lscan lscan

-- | Variant of 'lscanComp' useful with size-indexed functors
lscanComp' :: (Zippable g, Functor g, Functor f, Monoid a) =>
              LScanTy g -> LScanTy f
           -> g (f a) -> (g (f a), a)
lscanComp' lscanG lscanF gfa  = (zipWith adjustl tots' gfa', tot)
 where
   (gfa' ,tots)  = unzip (lscanF <$> gfa)
   (tots',tot)   = lscanG tots

adjustl :: (Monoid a, Functor t) => a -> t a -> t a
adjustl p = fmap (p <>)

-- | Scan a composition of functors
lscanComp :: (LScan g, LScan f, Zippable g, Monoid a) =>
             g (f a) -> (g (f a), a)
lscanComp = lscanComp' lscan lscan

-- lscanComp gfa  = (zipWith adjust tots' gfa', tot)
--  where
--    (gfa' ,tots)  = unzip (lscan <$> gfa)
--    (tots',tot)   = lscan tots
--    adjust (p,t)  = (p <>) <$> t

shiftL :: Traversable t => (t a, a) -> (a, t a)
shiftL (as,a') = mapAccumR (flip (,)) a' as

shiftR :: Traversable t => (a, t a) -> (t a, a)
shiftR (a',as) = swap (mapAccumL (flip (,)) a' as)
 where
   swap (x,y) = (y,x)

lscanInc :: (LScan f, Traversable f, Monoid b) => Unop (f b)
lscanInc = snd . shiftL . lscan

-- lsums :: (LScan f, Num b) => f b -> (f b, b)
lsums :: (LScan f, Num b) => f b -> (f b, b)
lsums = (fmap getSum *** getSum) . lscan . fmap Sum

lproducts :: (LScan f, Traversable f, Num b) => f b -> (f b, b)
lproducts = (fmap getProduct *** getProduct) . lscan . fmap Product

-- Variants 

lsums' :: (LScan f, Traversable f, Num b) => Unop (f b)
lsums' = snd . shiftL . lsums
-- lsums' = fmap getSum . lscanInc . fmap Sum

lproducts' :: (LScan f, Traversable f, Num b) => Unop (f b)
lproducts' = snd . shiftL . lproducts
-- lproducts' = fmap getProduct . lscanInc . fmap Product

class Zippable f where
  zip :: f a-> f b -> f (a,b)
  -- Temporary hack to avoid newtype-like representation.
  zippableDummy :: f a
  zippableDummy = undefined

-- zipA :: Applicative f => (f a, f b) -> f (a,b)
-- zipA = uncurry (liftA2 (,))

unzip :: Functor f => f (a,b) -> (f a, f b)
unzip ps = (fst <$> ps, snd <$> ps)

zipWith :: (Functor f, Zippable f) => (a -> b -> c) -> f a -> f b -> f c
zipWith h as bs = uncurry h <$> zip as bs

{--------------------------------------------------------------------
    From Data.Traversable
--------------------------------------------------------------------}

-- I had to copy this code, because Data.Traversable doesn't export StateR, and
-- I need a HasRep instance.
-- TODO: Fix compilation to synthesize HasRep instances when they're missing.

-- left-to-right state transformer
newtype StateL s a = StateL { runStateL :: s -> (s, a) }

instance Functor (StateL s) where
    fmap f (StateL k) = StateL $ \ s -> let (s', v) = k s in (s', f v)

instance Applicative (StateL s) where
    pure x = StateL (\ s -> (s, x))
    StateL kf <*> StateL kv = StateL $ \ s ->
        let (s', f) = kf s
            (s'', v) = kv s'
        in (s'', f v)

-- |The 'mapAccumL' function behaves like a combination of 'fmap'
-- and 'foldl'; it applies a function to each element of a structure,
-- passing an accumulating parameter from left to right, and returning
-- a final value of this accumulator together with the new structure.
mapAccumL :: Traversable t => (a -> b -> (a, c)) -> a -> t b -> (a, t c)
mapAccumL f s t = runStateL (traverse (StateL . flip f) t) s

-- right-to-left state transformer
newtype StateR s a = StateR { runStateR :: s -> (s, a) }

instance Functor (StateR s) where
    fmap f (StateR k) = StateR $ \ s -> let (s', v) = k s in (s', f v)

instance Applicative (StateR s) where
    pure x = StateR (\ s -> (s, x))
    StateR kf <*> StateR kv = StateR $ \ s ->
        let (s', v) = kv s
            (s'', f) = kf s'
        in (s'', f v)

-- |The 'mapAccumR' function behaves like a combination of 'fmap'
-- and 'foldr'; it applies a function to each element of a structure,
-- passing an accumulating parameter from right to left, and returning
-- a final value of this accumulator together with the new structure.
mapAccumR :: Traversable t => (a -> b -> (a, c)) -> a -> t b -> (a, t c)
mapAccumR f s t = runStateR (traverse (StateR . flip f) t) s

-- Add HasRep instances

type instance Rep (StateL s a) = s -> (s, a)
instance HasRep (StateL s a) where
  abst = StateL
  repr = runStateL

type instance Rep (StateR s a) = s -> (s, a)
instance HasRep (StateR s a) where
  abst = StateR
  repr = runStateR