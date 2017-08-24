module Data.Bytes

import Data.ByteArray as BA

%access export
%default total

-- Structure of the allocated ByteArray
--   [used_size][.....data.....]
-- used_size is an int and it takes up BA.bytesPerInt bytes
-- at the beginning of the array

record Bytes where
  constructor B
  arr : ByteArray
  ofs : Int
  end : Int  -- first offset not included in the array

private
minimalCapacity : Int
minimalCapacity = 16

private
dataOfs : Int
dataOfs = 1 * BA.bytesPerInt

private
allocate : Int -> IO Bytes
allocate capacity = do
  arr <- BA.allocate (BA.bytesPerInt + capacity)
  BA.pokeInt 0 dataOfs arr
  BA.fill dataOfs capacity 0 arr  -- zero the array
  pure $ B arr dataOfs dataOfs

length : Bytes -> Nat
length (B arr ofs end) = cast $ end - ofs

empty : Bytes
empty = unsafePerformIO $ allocate minimalCapacity

null : Bytes -> Bool
null (B arr ofs end) = (ofs == end)

%freeze empty

-- factor=1 ~ copy
-- factor=2 ~ grow
private
grow : Int -> Bytes -> IO Bytes
grow factor (B arr ofs end) = do
  maxUsed <- BA.peekInt 0 arr
  let bytesUsed = end - ofs
  let bytesAvailable =
        if maxUsed > end
          then bytesUsed
          else BA.size arr - ofs
  B arr' ofs' end' <- allocate $ (factor*bytesAvailable) `max` minimalCapacity
  BA.copy (arr, ofs) (arr', ofs') bytesUsed
  pure $ B arr' ofs' (ofs' + bytesUsed)

%assert_total
snoc : Bytes -> Byte -> Bytes
snoc bs@(B arr ofs end) byte
    = if end >= BA.size arr
        then unsafePerformIO $ do  -- need more space
          grown <- grow 2 bs
          pure $ snoc grown byte
        else unsafePerformIO $ do
          maxUsed <- BA.peekInt 0 arr
          if maxUsed > end
            then do  -- someone already took the headroom, need copying
              copy <- grow 2 bs
              pure $ snoc copy byte
            else do  -- can mutate
              BA.pokeInt 0 (end+1) arr
              BA.poke end byte arr
              pure $ B arr ofs (end+1)

infixl 7 |>
(|>) : Bytes -> Byte -> Bytes
(|>) = snoc

namespace SnocView
  public export
  data SnocView : Type where
    Nil : SnocView
    Snoc : (bs : Bytes) -> (b : Byte) -> SnocView

  snocView : Bytes -> SnocView
  snocView (B arr ofs end) =
    if end == ofs
      then SnocView.Nil
      else unsafePerformIO $ do
        last <- BA.peek (end-1) arr
        pure $ SnocView.Snoc (B arr ofs (end-1)) last

namespace ConsView
  public export
  data ConsView : Type where
    Nil : ConsView
    Cons : (b : Byte) -> (bs : Bytes) -> ConsView

  consView : Bytes -> ConsView
  consView (B arr ofs end) =
    if end == ofs
      then ConsView.Nil
      else unsafePerformIO $ do
        first <- BA.peek ofs arr
        pure $ ConsView.Cons first (B arr (ofs+1) end)

infixr 7 ++
%assert_total
(++) : Bytes -> Bytes -> Bytes
(++) bsL@(B arrL ofsL endL) bsR@(B arrR ofsR endR)
  = let countR = endR - ofsR in
      if endL + countR > BA.size arrL
        then unsafePerformIO $ do  -- need more space
          grown <- grow 2 bsL
          pure $ grown ++ bsR
        else unsafePerformIO $ do
          maxUsedL <- BA.peekInt 0 arrL
          if maxUsedL > endL
            then do  -- headroom taken
              copyL <- grow 2 bsL
              pure $ copyL ++ bsR
            else do  -- can mutate
              BA.pokeInt 0 (endL + countR) arrL
              BA.copy (arrR, ofsR) (arrL, endL) countR
              pure $ B arrL ofsL (endL + countR)

dropPrefix : Int -> Bytes -> Bytes
dropPrefix n (B arr ofs end) = B arr (((ofs + n) `min` end) `max` dataOfs) end

takePrefix : Int -> Bytes -> Bytes
takePrefix n (B arr ofs end) = B arr ofs (((ofs + n) `min` end) `max` dataOfs)

pack : List Byte -> Bytes
pack = fromList empty
  where
    fromList : Bytes -> List Byte -> Bytes
    fromList bs []        = bs
    fromList bs (x :: xs) = fromList (bs `snoc` x) xs

unpack : Bytes -> List Byte
unpack bs with (consView bs)
  | Nil       = []
  | Cons x xs = x :: unpack (assert_smaller bs xs)

slice : Int -> Int -> Bytes -> Bytes
slice ofs' end' (B arr ofs end)
  = B arr
        (((ofs + ofs') `min` end) `max` dataOfs)
        (((ofs + end') `min` end) `max` dataOfs)

-- Folds with early exit.
-- If Bytes were a Functor, this would be equivalent
-- to a Traversable implementation interpreted in the Either monad.
public export
data Result : Type -> Type where
  Stop : (result : a) -> Result a
  Cont : (acc : a) -> Result a

iterateR : (Byte -> a -> Result a) -> a -> Bytes -> a
iterateR f acc bs with (snocView bs)
  | Nil       = acc
  | Snoc ys y with (f y acc)
    | Stop result = result
    | Cont acc'   = iterateR f acc' (assert_smaller bs ys)

iterateL : (a -> Byte -> Result a) -> a -> Bytes -> a
iterateL f acc bs with (consView bs)
  | Nil       = acc
  | Cons y ys with (f acc y)
    | Stop result = result
    | Cont acc'   = iterateL f acc' (assert_smaller bs ys)

infixl 3 .:
private
(.:) : (a -> b) -> (c -> d -> a) -> (c -> d -> b)
(.:) g f x y = g (f x y)

foldr : (Byte -> a -> a) -> a -> Bytes -> a
foldr f = iterateR (Cont .: f)

foldl : (a -> Byte -> a) -> a -> Bytes -> a
foldl f = iterateL (Cont .: f)

spanLength : (Byte -> Bool) -> Bytes -> Int
spanLength p = iterateL step 0
  where
    step : Int -> Byte -> Result Int
    step n b with (p b)
      | True  = Cont (1 + n)
      | False = Stop n

find : Byte -> Bytes -> Maybe Int
find b (B arr ofs end) = unsafePerformIO $ BA.find b arr ofs end

splitAt : Int -> Bytes -> (Bytes, Bytes)
splitAt n bs = (takePrefix n bs, dropPrefix n bs)

splitOn : Byte -> Bytes -> (Bytes, Bytes)
splitOn b bs with (find b bs)
  | Nothing  = (bs, empty)
  | Just ofs = (takePrefix ofs bs, dropPrefix (ofs+1) bs)

splitsOn : Byte -> Bytes -> List Bytes
splitsOn b bs with (find b bs)
  | Nothing  = [bs]
  | Just ofs = takePrefix ofs bs :: splitsOn b (assert_smaller bs $ dropPrefix (ofs+1) bs)

asciiLines : Bytes -> List Bytes
asciiLines = splitsOn 0x0A

span : (Byte -> Bool) -> Bytes -> (Bytes, Bytes)
span p bs = splitAt (spanLength p bs) bs

break : (Byte -> Bool) -> Bytes -> (Bytes, Bytes)
break p bs = span (not . p) bs

private
cmp : Bytes -> Bytes -> Ordering
cmp (B arrL ofsL endL) (B arrR ofsR endR) = unsafePerformIO $ do
    let countL = endL - ofsL
    let countR = endR - ofsR
    let commonCount = countL `min` countR
    result <- BA.compare (arrL, ofsL) (arrR, ofsR) commonCount
    pure $
      if result /= 0
        then i2o result
        else compare countL countR
  where
    i2o : Int -> Ordering
    i2o 0 = EQ
    i2o i = if i < 0 then LT else GT

implementation Eq Bytes where
  xs == ys = (Bytes.cmp xs ys == EQ)

implementation Ord Bytes where
  compare = Bytes.cmp

toString : Bytes -> String
toString = foldr (strCons . chr . toInt) ""

fromString : String -> Bytes
fromString = foldl (\bs, c => bs |> fromInt (ord c)) empty . unpack

implementation Show Bytes where
  show = ("b" ++) . show . toString

implementation Semigroup Bytes where
  (<+>) = (++)

implementation Monoid Bytes where
  neutral = empty

-- todo:
--
-- make indices Nats
-- Build a ByteString on top of Bytes?
-- migrate to (Bits 8)?
--
-- bidirectional growth?
