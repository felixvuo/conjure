{-# LANGUAGE QuasiQuotes, ViewPatterns, OverloadedStrings  #-}

module Language.E.Up.Common(
    transposeE,
    unwrapMatrix,
    matrixToTuple
) where

import qualified Data.List as L(transpose)

import Language.E
import Language.E.Up.Debug


transposeE :: [E] -> [E]
-- transposeE e | 1 == 3  `_p` ("tranposeE args", e ) = undefined

transposeE arr  |  all isLiteral arr =
    let arr2D = map tranposeCheck arr
        res = L.transpose arr2D
    in  map (\ele -> [xMake| value.matrix.values := ele |] ) res

transposeE e = e

tranposeCheck :: E -> [E]
tranposeCheck   [xMatch| vs := value.matrix.values |] = vs

-- This is actually needed for very few cases such as tupley26
-- need to make more specific
tranposeCheck e@[xMatch| _ := value.tuple.values  |] =
    let res = convertTuples e
    in  unwrapMatrix res
        `_p` ("USING tranposeCheck tuples", [res])

tranposeCheck e = errbM "tranposeCheck" [e]


convertTuples :: E -> E
convertTuples [xMatch| vs := value.tuple.values |] =
    let res  = map matrixToTuple (transposeE vs)
        res' = [xMake| value.matrix.values := res |]
    in res'

convertTuples (e) = e

isLiteral ::  E -> Bool
isLiteral [xMatch| _ := value.literal |] = False
isLiteral  _ = True

unwrapMatrix :: E -> [E]
unwrapMatrix [xMatch| vs := value.matrix.values |] = vs

matrixToTuple :: E -> E
matrixToTuple [xMatch| vs := value.matrix|] = [xMake| value.tuple := vs |]

