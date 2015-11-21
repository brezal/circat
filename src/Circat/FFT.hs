{-# LANGUAGE CPP, Rank2Types, TypeOperators #-}
{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ConstraintKinds, ParallelListComp #-}
{-# LANGUAGE FlexibleContexts, TypeSynonymInstances #-}
{-# LANGUAGE GADTs #-}

{-# LANGUAGE UndecidableInstances #-} -- See below

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP

#define TESTING

#ifdef TESTING
{-# OPTIONS_GHC -fno-warn-unused-binds   #-} -- TEMP
#endif

----------------------------------------------------------------------
-- |
-- Module      :  Circat.FFT
-- Copyright   :  (c) 2015 Conal Elliott
--
-- Maintainer  :  conal@conal.net
-- Stability   :  experimental
-- 
-- Generic FFT
----------------------------------------------------------------------

module Circat.FFT
  ( Sized(..), sizeAF, FFT(..)
  ) where

-- TODO: explicit exports

import Prelude hiding (sum)

import Data.Functor ((<$>))
import Data.Foldable (Foldable,sum,toList)
import Data.Traversable
import Control.Applicative (Applicative(..),liftA2)
import Data.Complex (Complex(..))

import Control.Compose ((:.)(..),inO,unO)
import TypeUnary.Nat (Nat(..),IsNat(..),natToZ,N0,N1,N2)
import TypeUnary.Vec hiding (transpose)

import Data.Newtypes.PrettyDouble

import Circat.Misc (transpose, inTranspose,Unop)
import Circat.Scan (LScan,lproducts,lsums,scanlT)
import Circat.Pair
import qualified Circat.LTree as L
import qualified Circat.RTree as R

{--------------------------------------------------------------------
    Statically sized functors
--------------------------------------------------------------------}

class Sized f where
  size :: f () -> Int -- ^ Argument is ignored at runtime

-- TODO: Switch from f () to f Void

-- The argument to size is unfortunate. When GHC Haskell has explicit type
-- application (<https://ghc.haskell.org/trac/ghc/wiki/TypeApplication>),
-- replace "size (undefined :: f ())" with "size @f".
-- Meanwhile, a macro helps.

#define tySize(f) (size (undefined :: (f) ()))

-- | Useful default for 'size'.
sizeAF :: forall f. (Applicative f, Foldable f) => f () -> Int
sizeAF = const (sum (pure 1 :: f Int))

instance Sized Pair where size = const 2

instance (Sized g, Sized f) => Sized (g :. f) where
  size = const (tySize(g) * tySize(f))

instance IsNat n => Sized (L.Tree n) where
  size = const (twoNat (nat :: Nat n))

instance IsNat n => Sized (R.Tree n) where
  size = const (twoNat (nat :: Nat n))

-- | @2 ^ n@
twoNat :: Integral m => Nat n -> m
twoNat n = 2 ^ (natToZ n :: Int)

-- TODO: Generalize from Pair in L.Tree and R.Tree

-- TODO: Try using sizeAF instead of size, and see what happens. I think it'd
-- work but be much slower, either at compile- or run-time.

{--------------------------------------------------------------------
    FFT
--------------------------------------------------------------------}

type DFTTy f f' = forall a. RealFloat a => f (Complex a) -> f' (Complex a)

class FFT f f' | f -> f' where
  fft :: DFTTy f f'

instance ( Applicative f , Traversable f , Traversable g
         , Applicative f', Applicative g', Traversable g'
         , FFT f f', FFT g g', LScan f, LScan g', Sized f, Sized g' )
      => FFT (g :. f) (f' :. g') where
  fft = inO (transpose . fmap fft . twiddle . inTranspose (fmap fft))

-- Without UndecidableInstances, I get the following:
-- 
--     Illegal instance declaration for ‘FFT (g :. f) (f' :. g')’
--       The coverage condition fails in class ‘FFT’
--         for functional dependency: ‘f -> f'’
--       Reason: lhs type ‘g :. f’ does not determine rhs type ‘f' :. g'’
--       Using UndecidableInstances might help
--     In the instance declaration for ‘FFT (g :. f) (f' :. g')’
--
-- What's going on here? Compiler bug? Misleading error message?

#if 0

-- Types in fft for (g :. f):

unO       :: (g :. f) a -> g  (f  a)
transpose :: g  (f  a)  -> f  (g  a)
fmap onG  :: f  (g  a)  -> f  (g' a)
transpose :: f  (g' a)  -> g' (f  a)
twiddle   :: g' (f  a)  -> g' (f  a)
fmap onF  :: g' (f  a)  -> g' (f' a)
transpose :: g' (f' a)  -> f' (g' a)
O         :: g  (f a)   -> (g :. f) a

#endif

type AFS h = (Applicative h, Foldable h, Sized h, LScan h)

twiddle :: (AFS g, AFS f, RealFloat a) => Unop (g (f (Complex a)))
twiddle = (liftA2.liftA2) (*) twiddles

-- Twiddle factors.
twiddles :: forall g f a. (AFS g, AFS f, RealFloat a) => g (f (Complex a))
twiddles = powers <$> powers (omega (tySize(g :. f)))

omega :: (Integral n, RealFloat a) => n -> Complex a
omega n = exp (- 2 * (0:+1) * pi / fromIntegral n)

-- Powers of x, starting x^0. Uses 'LScan' for log parallel time
powers :: (LScan f, Applicative f, Num a) => a -> f a
powers = fst . lproducts . pure

-- TODO: Consolidate with powers in TreeTest and rename sensibly. Maybe use
-- "In" and "Ex" suffixes to distinguish inclusive and exclusive cases.

{--------------------------------------------------------------------
    Specialized FFT instances
--------------------------------------------------------------------}

-- Radix 2 butterfly
instance FFT Pair Pair where
  fft (a :# b) = (a + b) :# (a - b)

-- Handle trees by conversion to functor compositions.

instance IsNat n => FFT (L.Tree n) (R.Tree n) where
  fft = fft' nat
   where
     fft' :: Nat m -> DFTTy (L.Tree m) (R.Tree m)
     fft' Zero     = R.L          .        L.unL
     fft' (Succ _) = R.B . unO . fft . O . L.unB

instance IsNat n => FFT (R.Tree n) (L.Tree n) where
  fft = fft' nat
   where
     fft' :: Nat m -> DFTTy (R.Tree m) (L.Tree m)
     fft' Zero     = L.L          .        R.unL
     fft' (Succ _) = L.B . unO . fft . O . R.unB

-- TODO: Do these instances amount to DIT and DIF respectively?
-- TODO: Remove the boilerplate via DeriveGeneric.
-- TODO: functor products and sums
-- TODO: Pair via Identity and functor product.

#ifdef TESTING

{--------------------------------------------------------------------
    Simple, quadratic DFT (for specification & testing)
--------------------------------------------------------------------}

-- Adapted from Dave's definition
dft :: RealFloat a => Unop [Complex a]
dft xs = [ sum [ x * ok^n | x <- xs | n <- [0 :: Int ..] ]
         | k <- [0 .. length xs - 1], let ok = om ^ k ]
 where
   om = omega (length xs)

{--------------------------------------------------------------------
    Tests
--------------------------------------------------------------------}

-- > powers 2 :: L.Tree N2 Int
-- B (B (L ((1 :# 2) :# (4 :# 8))))
-- > powers 2 :: L.Tree N3 Int
-- B (B (B (L (((1 :# 2) :# (4 :# 8)) :# ((16 :# 32) :# (64 :# 128))))))

type C = Complex PrettyDouble

fftl :: (FFT f f', Foldable f', RealFloat a) => f (Complex a) -> [Complex a]
fftl = toList . fft

type LC n = L.Tree n C
type RC n = R.Tree n C

p1 :: Pair C
p1 = 1 :# 0

tw1 :: L.Tree N1 (Pair C)
tw1 = twiddles

tw2 :: L.Tree N2 (Pair C)
tw2 = twiddles

-- Adapted from Dave's testing

test :: (FFT f f', Foldable f, Foldable f') => f C -> IO ()
test fx =
  do ps "\nTesting input" xs
     ps "Expected output" (dft xs)
     ps "Actual output  " (toList (fft fx))
 where
   ps label z = putStrLn (label ++ ": " ++ show z)
   xs = toList fx

t0 :: LC N0
t0 = L.fromList [1]

t1 :: LC N1
t1 = L.fromList [1, 0]

t2s :: [LC N2]
t2s = L.fromList <$>
        [ [1,  0,  0,  0]  -- Delta
        , [1,  1,  1,  1]  -- Constant
        , [1, -1,  1, -1]  -- Nyquist
        , [1,  0, -1,  0]  -- Fundamental
        , [0,  1,  0, -1]  -- Fundamental w/ 90-deg. phase lag
       ]

tests :: IO ()
tests = do test p1
           test t0
           test t1
           mapM_ test t2s

-- end of tests
#endif

