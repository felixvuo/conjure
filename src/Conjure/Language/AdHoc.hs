{-# LANGUAGE MultiParamTypeClasses #-}

module Conjure.Language.AdHoc where

import Conjure.Prelude
import Conjure.Language.Name


class ExpressionLike a where
    fromInt :: Integer -> a
    intOut :: MonadFail m => a -> m Integer

    fromBool :: Bool -> a
    boolOut :: MonadFail m => a -> m Bool

    fromList :: [a] -> a
    listOut :: MonadFail m => a -> m [a]

class ReferenceContainer a where
    fromName :: Name -> a
    nameOut :: MonadFail m => a -> m Name

class DomainContainer a dom where
    fromDomain :: dom a -> a
    domainOut :: MonadFail m => a -> m (dom a)

class CanBeAnAlias a where
    isAlias :: a -> Maybe a
