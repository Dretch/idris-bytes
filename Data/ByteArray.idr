module Data.ByteArray

%include C "array.h"
%link C "array.o"

%access public
%default total

namespace Byte
  Byte : Type
  Byte = Bits8

  toInt : Byte -> Int
  toInt = prim__zextB8_Int

  fromInt : Int -> Byte
  fromInt = prim__truncInt_B8

abstract
record ByteArray where
  constructor BA
  ptr : CData
  sz : Int

-- This needn't be precise; it just needs to be enough to be safe.
abstract
bytesPerInt : Int
bytesPerInt = 8

abstract
allocate : Int -> IO ByteArray
allocate sz = do
  ptr <- foreign FFI_C "array_alloc" (Int -> IO CData) sz
  return $ BA ptr sz

abstract
peek : Int -> ByteArray -> IO Byte
peek ofs (BA ptr sz)
  = if (ofs < 0 || ofs >= sz)
      then return 0
      else foreign FFI_C "array_peek" (Int -> CData -> IO Byte) ofs ptr

abstract
peekInt : Int -> ByteArray -> IO Int
peekInt ofs (BA ptr sz)
  = if (ofs < 0 || ofs+bytesPerInt >= sz)
      then return 0
      else foreign FFI_C "array_peek_int" (Int -> CData -> IO Int) ofs ptr

abstract
poke : Int -> Byte -> ByteArray -> IO ()
poke ofs b (BA ptr sz)
  = if (ofs < 0 || ofs >= sz)
      then return ()
      else foreign FFI_C "array_poke" (Int -> Byte -> CData -> IO ()) ofs b ptr

abstract
pokeInt : Int -> Int -> ByteArray -> IO ()
pokeInt ofs i (BA ptr sz)
  = if (ofs < 0 || ofs >= sz)
      then return ()
      else foreign FFI_C "array_poke_int" (Int -> Int -> CData -> IO ()) ofs i ptr

abstract
copy : (ByteArray, Int) -> (ByteArray, Int) -> Int -> IO ()
copy (BA srcPtr srcSz, srcIx) (BA dstPtr dstSz, dstIx) count
  = if (srcIx < 0 || dstIx < 0 || (srcIx+count) >= srcSz || (dstIx+count) >= dstSz)
      then return ()
      else foreign FFI_C "array_copy" (CData -> Int -> CData -> Int -> Int -> IO ()) srcPtr srcIx dstPtr dstIx count

abstract
fill : Int -> Int -> Byte -> ByteArray -> IO ()
fill ofs count b (BA ptr sz)
  = if (ofs < 0 || ofs+count >= sz)
      then return ()
      else foreign FFI_C "array_fill" (Int -> Int -> Byte -> CData -> IO ()) ofs count b ptr

abstract
size : ByteArray -> Int
size (BA ptr sz) = sz
