{-# LANGUAGE CPP #-}
{-# LANGUAGE GADTs, FlexibleInstances, FlexibleContexts, Rank2Types #-}
{-# LANGUAGE TypeFamilies, TypeOperators #-}
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
  ( Zippable(..)
  , LScanTy, LScan(..), lscanInc
  , lsums, lproducts, lAlls, lAnys, lParities, lsums', lproducts', iota
  , lscanProd, lscanProd', lscanComp, lscanComp'
  , scanlT, scanlTEx
  ) where

import Prelude hiding (zip,unzip,zipWith)

import Data.Monoid (Monoid(..),(<>),Sum(..),Product(..),All(..),Any(..))
import Data.Functor ((<$>))
import Control.Arrow ((***)) -- ,first
import Data.Traversable (Traversable(..)) -- ,mapAccumR
import Control.Applicative (Applicative(..),liftA2)
import Data.Tuple (swap)

import TypeUnary.Vec (Vec(..),IsNat)

import Circat.Misc (Unop,(:*),Parity(..))
import Circat.Shift (shiftR,mapAccumL)

-- | Generalize the Prelude's 'scanl' on lists
scanlT :: Traversable t => (b -> a -> b) -> b -> t a -> (t b,b)
scanlT op e = swap . mapAccumL (\ a b -> (a `op` b,a)) e

-- | Like 'scanlT', but drop the last element.
scanlTEx :: Traversable t => (b -> a -> b) -> b -> t a -> t b
scanlTEx op e = fst . scanlT op e

type LScanTy f = forall a. Monoid a => f a -> f a :* a

class Functor f => LScan f where
  lscan :: LScanTy f
  -- Temporary hack to avoid newtype-like representation.
  lscanDummy :: f a
  lscanDummy = undefined

#if 0

-- Do we want this instance? It's sequential, and I think it matches scanlT.

instance LScan (Vec n) where
  lscan = lscanV' mempty
  {-# INLINE lscan #-}

lscanV' :: Monoid a => a -> Vec n a -> Vec n a :* a
lscanV' x ZVec      = (ZVec, x)
lscanV' x (a :< as) = first (x :<) (lscanV' (x <> a) as)
{-# INLINE lscanV' #-}
#endif

-- | Scan a product of functors. See also 'lscanProd'.
lscanProd' :: (Functor g, Monoid a)
           => LScanTy f -> LScanTy g
           -> f a :* g a -> (f a :* g a) :* a
lscanProd' lscanF lscanG (fa,ga) = ((fa', adjust <$> ga'), adjust gx)
 where
   (fa',fx) = lscanF fa
   (ga',gx) = lscanG ga
   adjust   = (fx <>)

-- | Scan a product of functors. See also 'lscanProd''.
lscanProd :: (Functor g, Monoid a, LScan f, LScan g)
          => (f a :* g a) -> (f a :* g a) :* a
lscanProd = lscanProd' lscan lscan

-- | Variant of 'lscanComp' useful with size-indexed functors
lscanComp' :: (Zippable g, Functor g, Functor f, Monoid a) =>
              LScanTy g -> LScanTy f
           -> g (f a) -> g (f a) :* a
lscanComp' lscanG lscanF gfa  = (zipWith adjustl tots' gfa', tot)
 where
   (gfa' ,tots)  = unzip (lscanF <$> gfa)
   (tots',tot)   = lscanG tots

adjustl :: (Monoid a, Functor t) => a -> t a -> t a
adjustl p = fmap (p <>)

-- | Scan a composition of functors
lscanComp :: (LScan g, LScan f, Zippable g, Monoid a) =>
             g (f a) -> g (f a) :* a
lscanComp = lscanComp' lscan lscan

-- lscanComp gfa  = (zipWith adjust tots' gfa', tot)
--  where
--    (gfa' ,tots)  = unzip (lscan <$> gfa)
--    (tots',tot)   = lscan tots
--    adjust (p,t)  = (p <>) <$> t

lscanInc :: (LScan f, Traversable f, Monoid b) => Unop (f b)
lscanInc = snd . shiftR . lscan

lsums :: (LScan f, Num b) => f b -> (f b, b)
lsums = (fmap getSum *** getSum) . lscan . fmap Sum

lproducts :: (LScan f, Num b) => f b -> f b :* b
lproducts = (fmap getProduct *** getProduct) . lscan . fmap Product

lAlls :: LScan f => f Bool -> (f Bool, Bool)
lAlls = (fmap getAll *** getAll) . lscan . fmap All

lAnys :: LScan f => f Bool -> (f Bool, Bool)
lAnys = (fmap getAny *** getAny) . lscan . fmap Any

lParities :: LScan f => f Bool -> (f Bool, Bool)
lParities = (fmap getParity *** getParity) . lscan . fmap Parity

-- Variants 

-- | Numbers from 0 to n-1. Named for APL iota operation (but 0 based).
iota :: (LScan f, Traversable f, Applicative f, Num b) => f b
-- iota = lsums' (pure 1)
iota = fst (lsums (pure 1))

lsums' :: (LScan f, Traversable f, Num b) => Unop (f b)
lsums' = snd . shiftR . lsums
-- lsums' = fmap getSum . lscanInc . fmap Sum

lproducts' :: (LScan f, Traversable f, Num b) => Unop (f b)
lproducts' = snd . shiftR . lproducts
-- lproducts' = fmap getProduct . lscanInc . fmap Product

class Functor f => Zippable f where
  zipWith :: (a -> b -> c) -> f a -> f b -> f c
  zipWith h as bs = uncurry h <$> zip as bs
  zip :: f a -> f b -> f (a,b)
  zip = zipWith (,)
  {-# MINIMAL zip | zipWith #-}

instance IsNat n => Zippable (Vec n) where zipWith = liftA2

-- zipA :: Applicative f => (f a, f b) -> f (a,b)
-- zipA = uncurry (liftA2 (,))

unzip :: Functor f => f (a :* b) -> f a :* f b
unzip ps = (fst <$> ps, snd <$> ps)
