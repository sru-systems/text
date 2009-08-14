{-# LANGUAGE BangPatterns, FlexibleInstances, TypeSynonymInstances #-}
{-# OPTIONS_GHC -fno-enable-rewrite-rules #-}

import Test.QuickCheck
import Text.Show.Functions

import Data.Char
import Debug.Trace
import Text.Printf
import System.Environment
import Control.Applicative
import Control.Arrow
import Control.Monad
import Data.Word
import qualified Data.ByteString as B
import qualified Data.Text as T
import qualified Data.Text.Compat as T (breakSubstring)
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Encoding as E
import Control.Exception
import qualified Data.Text.Fusion as S
import qualified Data.Text.Fusion.Common as S
import qualified Data.Text.Lazy.Encoding as EL
import qualified Data.Text.Lazy.Fusion as SL
import qualified Data.List as L
import System.IO.Unsafe
import Prelude hiding (catch)

import QuickCheckUtils

-- If a pure property threatens to crash, wrap it with this to keep
-- QuickCheck from bombing out.
crashy :: a -> a -> a
{-# NOINLINE crashy #-}
crashy onException p = unsafePerformIO $
    (return $! p) `catch` \e ->
    let types = e :: SomeException
    in trace ("*** Exception: " ++ show e) return onException

prop_T_pack_unpack       = (T.unpack . T.pack) `eq` id
prop_TL_pack_unpack      = (TL.unpack . TL.pack) `eq` id
prop_T_stream_unstream   = (S.unstream . S.stream) `eq` id
prop_TL_stream_unstream  = (SL.unstream . SL.stream) `eq` id
prop_T_reverse_stream t  = (S.reverse . S.reverseStream) t == t
prop_T_singleton c       = [c] == (T.unpack . T.singleton) c
prop_TL_singleton c      = [c] == (TL.unpack . TL.singleton) c
prop_TL_unstreamChunks x = f 11 x == f 1000 x
    where f n = SL.unstreamChunks n . S.streamList
prop_TL_chunk_unchunk    = (TL.fromChunks . TL.toChunks) `eq` id

prop_T_ascii t           = E.decodeASCII (E.encodeUtf8 a) == a
    where a              = T.map (\c -> chr (ord c `mod` 128)) t
prop_T_utf8              = (E.decodeUtf8 . E.encodeUtf8) `eq` id
prop_TL_utf8             = (EL.decodeUtf8 . EL.encodeUtf8) `eq` id
prop_T_utf16LE           = (E.decodeUtf16LE . E.encodeUtf16LE) `eq` id
prop_T_utf16BE           = (E.decodeUtf16BE . E.encodeUtf16BE) `eq` id
prop_T_utf32LE           = (E.decodeUtf32LE . E.encodeUtf32LE) `eq` id
prop_T_utf32BE           = (E.decodeUtf32BE . E.encodeUtf32BE) `eq` id

class Stringy s where
    packS    :: String -> s
    unpackS  :: s -> String
    splitAtS :: Int -> s -> (s,s)
    packSChunkSize :: Int -> String -> s
    packSChunkSize _ = packS

instance Stringy String where
    packS    = id
    unpackS  = id
    splitAtS = splitAt

instance Stringy (S.Stream Char) where
    packS        = S.streamList
    unpackS      = S.unstreamList
    splitAtS n s = (S.take n s, S.drop n s)

instance Stringy T.Text where
    packS    = T.pack
    unpackS  = T.unpack
    splitAtS = T.splitAt

instance Stringy TL.Text where
    packSChunkSize k = SL.unstreamChunks k . S.streamList
    packS    = TL.pack
    unpackS  = TL.unpack
    splitAtS = TL.splitAt . fromIntegral

-- Do two functions give the same answer?
eq :: (Eq a) => (t -> a) -> (t -> a) -> t -> Bool
eq a b s  = crashy False $ a s == b s

-- What about with the RHS packed?
eqP :: (Eq a, Show a, Stringy s) =>
       (String -> a) -> (s -> a) -> String -> Word8 -> Bool
eqP a b s w  = eq "orig" (a s) (b t) &&
               eq "mini" (a s) (b mini) &&
               eq "head" (a sa) (b ta) &&
               eq "tail" (a sb) (b tb)
    where t             = packS s
          mini          = packSChunkSize 10 s
          (sa,sb)       = splitAt m s
          (ta,tb)       = splitAtS m t
          l             = length s
          m | l == 0    = n
            | otherwise = n `mod` l
          n             = fromIntegral w
          eq s a b | crashy False $ a == b = True
                   | otherwise = trace (s ++ ": " ++ show a ++ " /= " ++ show b) False

-- Or with the string non-empty, and the RHS packed?
eqEP :: (Eq a, Stringy s) =>
        (String -> a) -> (s -> a) -> NotEmpty String -> Word8 -> Bool
eqEP a b e w  = a s == b t &&
                a s == b mini &&
                (null sa || a sa == b ta) &&
                (null sb || a sb == b tb)
    where (sa,sb)       = splitAt m s
          (ta,tb)       = splitAtS m t
          t             = packS s
          mini          = packSChunkSize 10 s
          l             = length s
          m | l == 0    = n
            | otherwise = n `mod` l
          n             = fromIntegral w
          s             = notEmpty e

prop_S_cons x          = (x:)     `eqP` (unpackS . S.cons x)
prop_T_cons x          = (x:)     `eqP` (unpackS . T.cons x)
prop_TL_cons x         = ((x:)     `eqP` (TL.unpack . TL.cons x))
prop_S_snoc x          = (++ [x]) `eqP` (unpackS . (flip S.snoc) x)
prop_T_snoc x          = (++ [x]) `eqP` (unpackS . (flip T.snoc) x)
prop_TL_snoc x         = (++ [x]) `eqP` (unpackS . (flip TL.snoc) x)
prop_T_append s        = (s++)    `eqP` (unpackS . T.append (packS s))
prop_T_appendS s       = (s++)    `eqP` (unpackS . S.unstream . S.append (S.stream (packS s)) . S.stream)

uncons (x:xs) = Just (x,xs)
uncons _      = Nothing

prop_T_uncons s        = uncons   `eqP` (fmap (second unpackS) . T.uncons)
    where types = s :: String
prop_TL_uncons s       = uncons   `eqP` (fmap (second unpackS) . TL.uncons)
    where types = s :: String
prop_S_head            = head   `eqEP` S.head
prop_T_head            = head   `eqEP` T.head
prop_TL_head           = head   `eqEP` TL.head
prop_S_last            = last   `eqEP` S.last
prop_T_last            = last   `eqEP` T.last
prop_TL_last           = last   `eqEP` TL.last
prop_S_tail            = tail   `eqEP` (unpackS . S.tail)
prop_T_tail            = tail   `eqEP` (unpackS . T.tail)
prop_TL_tail           = tail   `eqEP` (unpackS . TL.tail)
prop_S_init            = init   `eqEP` (unpackS . S.init)
prop_T_init            = init   `eqEP` (unpackS . T.init)
prop_TL_init           = init   `eqEP` (unpackS . TL.init)
prop_S_null            = null   `eqP`  S.null
prop_T_null            = null   `eqP`  T.null
prop_TL_null           = null   `eqP`  TL.null
prop_S_length          = length `eqP`  S.length
prop_T_length          = length `eqP`  T.length
prop_TL_length         = length `eqP`  (fromIntegral . TL.length)
prop_T_map f           = map f  `eqP`  (unpackS . T.map f)
prop_TL_map f          = map f  `eqP`  (unpackS . TL.map f)
prop_T_intercalate c   = L.intercalate c `eq` (unpackS . T.intercalate (packS c) . map packS)
prop_TL_intercalate c  = L.intercalate c `eq` (unpackS . TL.intercalate (TL.pack c) . map TL.pack)
prop_T_intersperse c   = L.intersperse c `eqP` (unpackS . T.intersperse c)
prop_TL_intersperse c  = L.intersperse c `eqP` (unpackS . TL.intersperse c)
prop_T_transpose       = L.transpose `eq` (map unpackS . T.transpose . map packS)
prop_TL_transpose      = L.transpose `eq` (map unpackS . TL.transpose . map TL.pack)
prop_T_reverse         = L.reverse `eqP` (unpackS . T.reverse)
prop_TL_reverse        = L.reverse `eqP` (unpackS . TL.reverse)
prop_T_reverse_short n = L.reverse `eqP` (unpackS . S.reverse . shorten n . S.stream)

prop_T_replace s d     = (L.intercalate d . split s) `eqP` (unpackS . T.replace (T.pack s) (T.pack d))

split :: (Eq a) => [a] -> [a] -> [[a]]
split pat src0
    | l == 0    = [src0]
    | otherwise = go src0
  where
    l           = length pat
    go src      = search 0 src
      where
        search !n [] = [src]
        search !n s@(_:s')
            | pat `L.isPrefixOf` s = take n src : go (drop l s)
            | otherwise            = search (n+1) s'

prop_T_toCaseFold_length t = T.length (T.toCaseFold t) >= T.length t
prop_T_toLower_length t = T.length (T.toLower t) >= T.length t
prop_T_toLower_lower t = p (T.toLower t) >= p t
    where p = T.length . T.filter isLower
prop_T_toUpper_length t = T.length (T.toUpper t) >= T.length t
prop_T_toUpper_upper t = p (T.toUpper t) >= p t
    where p = T.length . T.filter isUpper

prop_T_justifyLeft k c = jl k c `eqP` (unpackS . T.justifyLeft k c)
    where jl k c s = s ++ replicate (k - length s) c
prop_T_justifyRight k c = jr k c `eqP` (unpackS . T.justifyRight k c)
    where jr k c s = replicate (k - length s) c ++ s

prop_T_foldl f z       = L.foldl f z  `eqP`  (T.foldl f z)
    where types        = f :: Char -> Char -> Char
prop_TL_foldl f z      = L.foldl f z  `eqP`  (TL.foldl f z)
    where types        = f :: Char -> Char -> Char
prop_T_foldl' f z      = L.foldl' f z `eqP`  T.foldl' f z
    where types        = f :: Char -> Char -> Char
prop_TL_foldl' f z     = L.foldl' f z `eqP`  TL.foldl' f z
    where types        = f :: Char -> Char -> Char
prop_T_foldl1 f        = L.foldl1 f   `eqEP` T.foldl1 f
prop_TL_foldl1 f       = L.foldl1 f   `eqEP` TL.foldl1 f
prop_T_foldl1' f       = L.foldl1' f  `eqEP` T.foldl1' f
prop_TL_foldl1' f      = L.foldl1' f  `eqEP` TL.foldl1' f
prop_T_foldr f z       = L.foldr f z  `eqP`  T.foldr f z
    where types        = f :: Char -> Char -> Char
prop_TL_foldr f z      = L.foldr f z  `eqP`  TL.foldr f z
    where types        = f :: Char -> Char -> Char
prop_T_foldr1 f        = L.foldr1 f   `eqEP` T.foldr1 f
prop_TL_foldr1 f       = L.foldr1 f   `eqEP` TL.foldr1 f

prop_T_concat          = L.concat      `eq`   (unpackS . T.concat . map packS)
prop_TL_concat         = L.concat      `eq`   (unpackS . TL.concat . map TL.pack)
prop_T_concatMap f     = L.concatMap f `eqP`  (unpackS . T.concatMap (packS . f))
prop_TL_concatMap f    = L.concatMap f `eqP`  (unpackS . TL.concatMap (TL.pack . f))
prop_T_any p           = L.any p       `eqP`  T.any p
prop_TL_any p          = L.any p       `eqP`  TL.any p
prop_T_all p           = L.all p       `eqP`  T.all p
prop_TL_all p          = L.all p       `eqP`  TL.all p
prop_T_maximum         = L.maximum     `eqEP` T.maximum
prop_TL_maximum        = L.maximum     `eqEP` TL.maximum
prop_T_minimum         = L.minimum     `eqEP` T.minimum
prop_TL_minimum        = L.minimum     `eqEP` TL.minimum

prop_T_scanl f z       = L.scanl f z   `eqP`  (unpackS . T.scanl f z)
prop_TL_scanl f z      = L.scanl f z   `eqP`  (unpackS . TL.scanl f z)
prop_T_scanl1 f        = L.scanl1 f    `eqP`  (unpackS . T.scanl1 f)
prop_TL_scanl1 f       = L.scanl1 f    `eqP`  (unpackS . TL.scanl1 f)
prop_T_scanr f z       = L.scanr f z   `eqP`  (unpackS . T.scanr f z)
prop_TL_scanr f z      = L.scanr f z   `eqP`  (unpackS . TL.scanr f z)
prop_T_scanr1 f        = L.scanr1 f    `eqP`  (unpackS . T.scanr1 f)
prop_TL_scanr1 f       = L.scanr1 f    `eqP`  (unpackS . TL.scanr1 f)

prop_T_mapAccumL f z   = L.mapAccumL f z `eqP` (second unpackS . T.mapAccumL f z)
    where types = f :: Int -> Char -> (Int,Char)
prop_TL_mapAccumL f z  = L.mapAccumL f z `eqP` (second unpackS . TL.mapAccumL f z)
    where types = f :: Int -> Char -> (Int,Char)
prop_T_mapAccumR f z   = L.mapAccumR f z `eqP` (second unpackS . T.mapAccumR f z)
    where types = f :: Int -> Char -> (Int,Char)
prop_TL_mapAccumR f z   = L.mapAccumR f z `eqP` (second unpackS . TL.mapAccumR f z)
    where types = f :: Int -> Char -> (Int,Char)

prop_T_replicate n     = L.replicate n `eq` (unpackS . T.replicate n)
prop_TL_replicate n    = L.replicate n `eq` (unpackS . TL.replicate n)

unf :: Int -> Char -> Maybe (Char, Char)
unf n c | fromEnum c * 100 > n = Nothing
        | otherwise            = Just (c, succ c)

prop_T_unfoldr n       = L.unfoldr (unf n) `eq` (unpackS . T.unfoldr (unf n))
prop_TL_unfoldr n      = L.unfoldr (unf n) `eq` (unpackS . TL.unfoldr (unf n))
prop_T_unfoldrN n m    = (L.take n . L.unfoldr (unf m)) `eq`
                         (unpackS . T.unfoldrN n (unf m))
prop_TL_unfoldrN n m   = (L.take n . L.unfoldr (unf m)) `eq`
                         (unpackS . TL.unfoldrN (fromIntegral n) (unf m))

unpack2 :: (Stringy s) => (s,s) -> (String,String)
unpack2 = unpackS *** unpackS

prop_S_take n          = L.take n      `eqP` (unpackS . S.take n)
prop_T_take n          = L.take n      `eqP` (unpackS . T.take n)
prop_TL_take n         = L.take n      `eqP` (unpackS . TL.take (fromIntegral n))
prop_S_drop n          = L.drop n      `eqP` (unpackS . S.drop n)
prop_T_drop n          = L.drop n      `eqP` (unpackS . T.drop n)
prop_TL_drop n         = L.drop n      `eqP` (unpackS . TL.drop n)
prop_S_takeWhile p     = L.takeWhile p `eqP` (unpackS . S.takeWhile p)
prop_T_takeWhile p     = L.takeWhile p `eqP` (unpackS . T.takeWhile p)
prop_TL_takeWhile p    = L.takeWhile p `eqP` (unpackS . TL.takeWhile p)
prop_S_dropWhile p     = L.dropWhile p `eqP` (unpackS . S.dropWhile p)
prop_T_dropWhile p     = L.dropWhile p `eqP` (unpackS . T.dropWhile p)
prop_TL_dropWhile p    = L.dropWhile p `eqP` (unpackS . S.dropWhile p)
prop_S_dropWhileEnd p  = T.dropWhileEnd p `eq` (S.reverse . S.dropWhile p . S.reverseStream)
prop_T_dropWhileEnd p  = (T.reverse . T.dropWhile p . T.reverse) `eq` T.dropWhileEnd p
prop_T_dropAround p    = (T.dropWhile p . T.dropWhileEnd p) `eq` T.dropAround p
prop_T_stripLeft       = T.dropWhile isSpace `eq` T.stripLeft
prop_T_stripRight      = T.dropWhileEnd isSpace `eq` T.stripRight
prop_T_strip           = T.dropAround isSpace `eq` T.strip
prop_T_splitAt n       = L.splitAt n   `eqP` (unpack2 . T.splitAt n)
prop_TL_splitAt n      = L.splitAt n   `eqP` (unpack2 . TL.splitAt (fromIntegral n))
prop_T_span p          = L.span p      `eqP` (unpack2 . T.span p)
prop_TL_span p         = L.span p      `eqP` (unpack2 . TL.span p)
prop_T_break p         = L.break p     `eqP` (unpack2 . T.break p)
prop_TL_break p        = L.break p     `eqP` (unpack2 . TL.break p)
prop_T_group           = L.group       `eqP` (map unpackS . T.group)
prop_TL_group          = L.group       `eqP` (map unpackS . TL.group)
prop_T_groupBy p       = L.groupBy p   `eqP` (map unpackS . T.groupBy p)
prop_TL_groupBy p      = L.groupBy p   `eqP` (map unpackS . TL.groupBy p)
prop_T_inits           = L.inits       `eqP` (map unpackS . T.inits)
prop_TL_inits          = L.inits       `eqP` (map unpackS . TL.inits)
prop_T_tails           = L.tails       `eqP` (map unpackS . T.tails)
prop_TL_tails          = L.tails       `eqP` (map unpackS . TL.tails)

prop_T_split_i t       = id `eq` (T.intercalate t . T.split t)
prop_T_splitTimes_i k t= id `eq` (T.intercalate t . T.splitTimes k t)
prop_T_splitTimesEnd_i k t = id `eq` (T.intercalate t . T.splitTimesEnd k t)
prop_TL_split_i c      = id `eq` (TL.intercalate (TL.singleton c) . TL.split c)

prop_T_splitWith p     = splitWith p `eqP` (map unpackS . T.splitWith p)
prop_T_splitWith_split c = T.splitWith (==c) `eq` T.split (T.singleton c)
prop_TL_splitWith p    = splitWith p `eqP` (map unpackS . TL.splitWith p)

splitWith :: (a -> Bool) -> [a] -> [[a]]
splitWith _ [] =  [[]]
splitWith p xs = loop xs
    where loop s | null s'   = [l]
                 | otherwise = l : loop (tail s')
              where (l, s') = break p s

prop_T_chunksOf_same_lengths k t
    = all ((==k) . T.length) . ini . T.chunksOf k $ t
  where ini [] = []
        ini xs = init xs

prop_T_chunksOf_length k t = let len = L.foldl' f 0 (T.chunksOf k t)
                             in  len == T.length t || (k <= 0 && len == 0)
    where f s t = T.length t + s

prop_T_breakSubstring_isInfixOf s l
                     = T.isInfixOf s l ==
                       T.null s || (not . T.null . snd $ T.breakSubstring s l)
prop_T_breakSubstringC c
                     = L.break (==c) `eqP`
                       (unpack2 . T.breakSubstring (T.singleton c))

prop_T_lines           = L.lines       `eqP` (map unpackS . T.lines)
prop_TL_lines          = L.lines       `eqP` (map unpackS . TL.lines)
{-
prop_T_lines'          = lines'        `eqP` (map unpackS . T.lines')
    where lines' "" =  []
          lines' s =  let (l, s') = break eol s
                      in  l : case s' of
                                []      -> []
                                ('\r':'\n':s'') -> lines' s''
                                (_:s'') -> lines' s''
          eol c = c == '\r' || c == '\n'
-}
prop_T_words           = L.words       `eqP` (map unpackS . T.words)
prop_TL_words          = L.words       `eqP` (map unpackS . TL.words)
prop_T_unlines         = L.unlines     `eq`  (unpackS . T.unlines . map packS)
prop_TL_unlines        = L.unlines     `eq`  (unpackS . TL.unlines . map packS)
prop_T_unwords         = L.unwords     `eq`  (unpackS . T.unwords . map packS)
prop_TL_unwords        = L.unwords     `eq`  (unpackS . TL.unwords . map packS)

prop_S_isPrefixOf s    = L.isPrefixOf s`eqP` (S.isPrefixOf (S.stream $ packS s) . S.stream)
prop_T_isPrefixOf s    = L.isPrefixOf s`eqP` T.isPrefixOf (packS s)
prop_TL_isPrefixOf s   = L.isPrefixOf s`eqP` TL.isPrefixOf (packS s)
prop_T_isSuffixOf s    = L.isSuffixOf s`eqP` T.isSuffixOf (packS s)
prop_TL_isSuffixOf s   = L.isSuffixOf s`eqP` TL.isSuffixOf (packS s)
prop_T_isInfixOf s     = L.isInfixOf s `eqP` T.isInfixOf (packS s)
prop_TL_isInfixOf s    = L.isInfixOf s `eqP` TL.isInfixOf (packS s)

prop_T_elem c          = L.elem c      `eqP` T.elem c
prop_TL_elem c         = L.elem c      `eqP` TL.elem c
prop_T_filter p        = L.filter p    `eqP` (unpackS . T.filter p)
prop_TL_filter p       = L.filter p    `eqP` (unpackS . TL.filter p)
prop_T_find p          = L.find p      `eqP` T.find p
prop_TL_find p         = L.find p      `eqP` TL.find p
prop_T_partition p     = L.partition p `eqP` (unpack2 . T.partition p)
prop_TL_partition p    = L.partition p `eqP` (unpack2 . TL.partition p)

prop_T_index x s       = x < L.length s && x >= 0 ==>
                         (L.!!) s x == T.index (packS s) x
prop_TL_index x s      = x < L.length s && x >= 0 ==>
                         (L.!!) s x == TL.index (packS s) (fromIntegral x)
prop_T_findIndex p     = L.findIndex p `eqP` T.findIndex p
prop_TL_findIndex p    = (fmap fromIntegral . L.findIndex p) `eqP` TL.findIndex p
prop_T_findIndices p   = L.findIndices p `eqP` T.findIndices p
prop_TL_findIndices p  = (fmap fromIntegral . L.findIndices p) `eqP` TL.findIndices p
prop_T_elemIndex c     = L.elemIndex c `eqP` T.elemIndex c
prop_TL_elemIndex c    = (fmap fromIntegral . L.elemIndex c) `eqP` TL.elemIndex c
prop_T_elemIndices c   = L.elemIndices c`eqP` T.elemIndices c
prop_TL_elemIndices c  = (fmap fromIntegral . L.elemIndices c) `eqP` TL.elemIndices c
prop_T_count c         = (L.length . L.elemIndices c) `eqP` T.count c
prop_TL_count c        = (fromIntegral . L.length . L.elemIndices c) `eqP` TL.count c
prop_T_zip s           = L.zip s `eqP` T.zip (packS s)
prop_TL_zip s          = L.zip s `eqP` TL.zip (packS s)
prop_T_zipWith c s     = L.zipWith c s `eqP` (unpackS . T.zipWith c (packS s))
prop_TL_zipWith c s    = L.zipWith c s `eqP` (unpackS . TL.zipWith c (packS s))

-- Regression tests.
prop_S_filter_eq s = S.filter p t == S.streamList (filter p s)
    where p = (/= S.last t)
          t = S.streamList s

-- Make a stream appear shorter than it really is, to ensure that
-- functions that consume inaccurately sized streams behave
-- themselves.
shorten :: Int -> S.Stream a -> S.Stream a
shorten n t@(S.Stream arr off len)
    | n < len && n > 0 = S.Stream arr off n
    | otherwise        = t

main = run tests =<< getArgs

run :: [(String, Int -> IO (Bool,Int))] -> [String] -> IO ()
run tests args = do
  let (n,names) = case args of
                    (k:ts) -> (read k,ts)
                    []  -> (100,[])
  (results,passed) <- fmap unzip . forM tests $ \(s,a) ->
                      if null names || s `elem` names
                      then printf "%-40s: " s >> a n
                      else return (True,0)
  printf "Passed %d tests!\n" (sum passed)
  when (not . and $ results) $
      fail "Not all tests passed!"

tests :: [(String, Int -> IO (Bool, Int))]
tests = [
  ("prop_T_pack_unpack", mytest prop_T_pack_unpack),
  ("prop_TL_pack_unpack", mytest prop_TL_pack_unpack),
  ("prop_T_stream_unstream", mytest prop_T_stream_unstream),
  ("prop_TL_stream_unstream", mytest prop_TL_stream_unstream),
  ("prop_T_reverse_stream", mytest prop_T_reverse_stream),
  ("prop_T_singleton", mytest prop_T_singleton),
  ("prop_TL_singleton", mytest prop_TL_singleton),
  ("prop_TL_unstreamChunks", mytest prop_TL_unstreamChunks),
  ("prop_TL_chunk_unchunk", mytest prop_TL_chunk_unchunk),

  ("prop_T_ascii", mytest prop_T_ascii),
  ("prop_T_utf8", mytest prop_T_utf8),
  ("prop_TL_utf8", mytest prop_TL_utf8),
  ("prop_T_utf16LE", mytest prop_T_utf16LE),
  ("prop_T_utf16BE", mytest prop_T_utf16BE),
  ("prop_T_utf32LE", mytest prop_T_utf32LE),
  ("prop_T_utf32BE", mytest prop_T_utf32BE),

  ("prop_S_cons", mytest prop_S_cons),
  ("prop_T_cons", mytest prop_T_cons),
  ("prop_TL_cons", mytest prop_TL_cons),
  ("prop_S_snoc", mytest prop_S_snoc),
  ("prop_T_snoc", mytest prop_T_snoc),
  ("prop_TL_snoc", mytest prop_TL_snoc),
  ("prop_T_append", mytest prop_T_append),
  ("prop_T_appendS", mytest prop_T_appendS),
  ("prop_T_uncons", mytest prop_T_uncons),
  ("prop_TL_uncons", mytest prop_TL_uncons),
  ("prop_S_head", mytest prop_S_head),
  ("prop_T_head", mytest prop_T_head),
  ("prop_TL_head", mytest prop_TL_head),
  ("prop_S_last", mytest prop_S_last),
  ("prop_T_last", mytest prop_T_last),
  ("prop_TL_last", mytest prop_TL_last),
  ("prop_S_tail", mytest prop_S_tail),
  ("prop_T_tail", mytest prop_T_tail),
  ("prop_TL_tail", mytest prop_TL_tail),
  ("prop_S_init", mytest prop_S_init),
  ("prop_T_init", mytest prop_T_init),
  ("prop_TL_init", mytest prop_TL_init),
  ("prop_S_null", mytest prop_S_null),
  ("prop_T_null", mytest prop_T_null),
  ("prop_TL_null", mytest prop_TL_null),
  ("prop_S_length", mytest prop_S_length),
  ("prop_T_length", mytest prop_T_length),
  ("prop_TL_length", mytest prop_TL_length),

  ("prop_T_map", mytest prop_T_map),
  ("prop_TL_map", mytest prop_TL_map),
  ("prop_T_intercalate", mytest prop_T_intercalate),
  ("prop_TL_intercalate", mytest prop_TL_intercalate),
  ("prop_T_intersperse", mytest prop_T_intersperse),
  ("prop_TL_intersperse", mytest prop_TL_intersperse),
  ("prop_T_transpose", mytest prop_T_transpose),
  ("prop_TL_transpose", mytest prop_TL_transpose),
  ("prop_T_reverse", mytest prop_T_reverse),
  ("prop_TL_reverse", mytest prop_TL_reverse),
  ("prop_T_reverse_short", mytest prop_T_reverse_short),
  ("prop_T_replace", mytest prop_T_replace),

  ("prop_T_toCaseFold_length", mytest prop_T_toCaseFold_length),
  ("prop_T_toLower_length", mytest prop_T_toLower_length),
  ("prop_T_toLower_lower", mytest prop_T_toLower_lower),
  ("prop_T_toUpper_length", mytest prop_T_toUpper_length),
  ("prop_T_toUpper_upper", mytest prop_T_toUpper_upper),

  ("prop_T_justifyLeft", mytest prop_T_justifyLeft),
  ("prop_T_justifyRight", mytest prop_T_justifyRight),

  ("prop_T_foldl", mytest prop_T_foldl),
  ("prop_TL_foldl", mytest prop_TL_foldl),
  ("prop_T_foldl'", mytest prop_T_foldl'),
  ("prop_TL_foldl'", mytest prop_TL_foldl'),
  ("prop_T_foldl1", mytest prop_T_foldl1),
  ("prop_TL_foldl1", mytest prop_TL_foldl1),
  ("prop_T_foldl1'", mytest prop_T_foldl1'),
  ("prop_TL_foldl1'", mytest prop_TL_foldl1'),
  ("prop_T_foldr", mytest prop_T_foldr),
  ("prop_TL_foldr", mytest prop_TL_foldr),
  ("prop_T_foldr1", mytest prop_T_foldr1),
  ("prop_TL_foldr1", mytest prop_TL_foldr1),

  ("prop_T_concat", mytest prop_T_concat),
  ("prop_TL_concat", mytest prop_TL_concat),
  ("prop_T_concatMap", mytest prop_T_concatMap),
  ("prop_TL_concatMap", mytest prop_TL_concatMap),
  ("prop_T_any", mytest prop_T_any),
  ("prop_TL_any", mytest prop_TL_any),
  ("prop_T_all", mytest prop_T_all),
  ("prop_TL_all", mytest prop_TL_all),
  ("prop_T_maximum", mytest prop_T_maximum),
  ("prop_TL_maximum", mytest prop_TL_maximum),
  ("prop_T_minimum", mytest prop_T_minimum),
  ("prop_TL_minimum", mytest prop_TL_minimum),

  ("prop_T_scanl", mytest prop_T_scanl),
  ("prop_TL_scanl", mytest prop_TL_scanl),
  ("prop_T_scanl1", mytest prop_T_scanl1),
  ("prop_TL_scanl1", mytest prop_TL_scanl1),
  ("prop_T_scanr", mytest prop_T_scanr),
  ("prop_TL_scanr", mytest prop_TL_scanr),
  ("prop_T_scanr1", mytest prop_T_scanr1),
  ("prop_TL_scanr1", mytest prop_TL_scanr1),

  ("prop_T_mapAccumL", mytest prop_T_mapAccumL),
  ("prop_TL_mapAccumL", mytest prop_TL_mapAccumL),
  ("prop_T_mapAccumR", mytest prop_T_mapAccumR),
  ("prop_TL_mapAccumR", mytest prop_TL_mapAccumR),

  ("prop_T_replicate", mytest prop_T_replicate),
  ("prop_TL_replicate", mytest prop_TL_replicate),
  ("prop_T_unfoldr", mytest prop_T_unfoldr),
  ("prop_TL_unfoldr", mytest prop_TL_unfoldr),
  ("prop_T_unfoldrN", mytest prop_T_unfoldrN),
  ("prop_TL_unfoldrN", mytest prop_TL_unfoldrN),

  ("prop_S_take", mytest prop_S_take),
  ("prop_T_take", mytest prop_T_take),
  ("prop_TL_take", mytest prop_TL_take),
  ("prop_S_drop", mytest prop_S_drop),
  ("prop_T_drop", mytest prop_T_drop),
  ("prop_TL_drop", mytest prop_TL_drop),
  ("prop_S_takeWhile", mytest prop_S_takeWhile),
  ("prop_T_takeWhile", mytest prop_T_takeWhile),
  ("prop_TL_takeWhile", mytest prop_TL_takeWhile),
  ("prop_S_dropWhile", mytest prop_S_dropWhile),
  ("prop_T_dropWhile", mytest prop_T_dropWhile),
  ("prop_TL_dropWhile", mytest prop_TL_dropWhile),
  ("prop_S_dropWhileEnd", mytest prop_S_dropWhileEnd),
  ("prop_T_dropWhileEnd", mytest prop_T_dropWhileEnd),
  ("prop_T_dropAround", mytest prop_T_dropAround),
  ("prop_T_stripLeft", mytest prop_T_stripLeft),
  ("prop_T_stripRight", mytest prop_T_stripRight),
  ("prop_T_strip", mytest prop_T_strip),
  ("prop_T_splitAt", mytest prop_T_splitAt),
  ("prop_T_span", mytest prop_T_span),
  ("prop_TL_span", mytest prop_TL_span),
  ("prop_T_break", mytest prop_T_break),
  ("prop_TL_break", mytest prop_TL_break),
  ("prop_T_group", mytest prop_T_group),
  ("prop_TL_group", mytest prop_TL_group),
  ("prop_T_groupBy", mytest prop_T_groupBy),
  ("prop_TL_groupBy", mytest prop_TL_groupBy),
  ("prop_T_inits", mytest prop_T_inits),
  ("prop_TL_inits", mytest prop_TL_inits),
  ("prop_T_tails", mytest prop_T_tails),
  ("prop_TL_tails", mytest prop_TL_tails),

  ("prop_T_split_i", mytest prop_T_split_i),
  ("prop_T_splitTimes_i", mytest prop_T_splitTimes_i),
  ("prop_T_splitTimesEnd_i", mytest prop_T_splitTimesEnd_i),
  ("prop_TL_split_i", mytest prop_TL_split_i),
  ("prop_T_splitWith", mytest prop_T_splitWith),
  ("prop_T_splitWith_split", mytest prop_T_splitWith_split),
  ("prop_TL_splitWith", mytest prop_TL_splitWith),
  ("prop_T_chunksOf_same_lengths", mytest prop_T_chunksOf_same_lengths),
  ("prop_T_chunksOf_length", mytest prop_T_chunksOf_length),
  ("prop_T_breakSubstringC", mytest prop_T_breakSubstringC),
  ("prop_T_breakSubstring_isInfixOf", mytest prop_T_breakSubstring_isInfixOf),

  ("prop_T_lines", mytest prop_T_lines),
  ("prop_TL_lines", mytest prop_TL_lines),
--("prop_T_lines'", mytest prop_T_lines'),
  ("prop_T_words", mytest prop_T_words),
  ("prop_TL_words", mytest prop_TL_words),
  ("prop_T_unlines", mytest prop_T_unlines),
  ("prop_TL_unlines", mytest prop_TL_unlines),
  ("prop_TL_unwords", mytest prop_TL_unwords),

  ("prop_S_isPrefixOf", mytest prop_S_isPrefixOf),
  ("prop_T_isPrefixOf", mytest prop_T_isPrefixOf),
  ("prop_TL_isPrefixOf", mytest prop_TL_isPrefixOf),
  ("prop_T_isSuffixOf", mytest prop_T_isSuffixOf),
  ("prop_TL_isSuffixOf", mytest prop_TL_isSuffixOf),
  ("prop_T_isInfixOf", mytest prop_T_isInfixOf),
  ("prop_TL_isInfixOf", mytest prop_TL_isInfixOf),

  ("prop_T_elem", mytest prop_T_elem),
  ("prop_TL_elem", mytest prop_TL_elem),
  ("prop_T_filter", mytest prop_T_filter),
  ("prop_TL_filter", mytest prop_TL_filter),
  ("prop_T_find", mytest prop_T_find),
  ("prop_TL_find", mytest prop_TL_find),
  ("prop_T_partition", mytest prop_T_partition),
  ("prop_TL_partition", mytest prop_TL_partition),

  ("prop_T_index", mytest prop_T_index),
  ("prop_T_findIndex", mytest prop_T_findIndex),
  ("prop_TL_findIndex", mytest prop_TL_findIndex),
  ("prop_T_findIndices", mytest prop_T_findIndices),
  ("prop_TL_findIndices", mytest prop_TL_findIndices),
  ("prop_T_elemIndex", mytest prop_T_elemIndex),
  ("prop_TL_elemIndex", mytest prop_TL_elemIndex),
  ("prop_T_elemIndices", mytest prop_T_elemIndices),
  ("prop_TL_elemIndices", mytest prop_TL_elemIndices),
  ("prop_T_count", mytest prop_T_count),
  ("prop_TL_count", mytest prop_TL_count),
  ("prop_T_zip", mytest prop_T_zip),
  ("prop_TL_zip", mytest prop_TL_zip),
  ("prop_T_zipWith", mytest prop_T_zipWith),
  ("prop_TL_zipWith", mytest prop_TL_zipWith),

  ("prop_S_filter_eq", mytest prop_S_filter_eq)
  ]
