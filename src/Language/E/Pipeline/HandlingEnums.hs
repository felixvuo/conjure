{-# LANGUAGE QuasiQuotes, ViewPatterns, OverloadedStrings #-}

module Language.E.Pipeline.HandlingEnums ( handleEnums ) where

import Language.E
import Language.E.Pipeline.ImplicitWheres


handleEnums :: MonadConjure m => Spec -> m Spec
handleEnums =
    handleEnumsLetting >=> return . doReplacements >=>
    handleEnumsGiven   >=> return . doReplacements >=>
    updateGivenFinds   >=>
    handleGivenIntDom  >=>
    handleInfiniteGivenDoms

-- replaces letting e be new type enum {a, b, c}
-- with     letting e_fromEnum be domain int(1..3)
-- returns ( the new spec
--         , (old E , new E)
--         )
handleEnumsLetting :: MonadConjure m => Spec -> m (Spec, [(E, E)])
handleEnumsLetting spec
    = runWriterT
    $ flip foreachStatement spec $ \ statement ->
        case statement of
            [xMatch| [Prim (S name)] := topLevel.letting.name.reference
                   | values          := topLevel.letting.typeEnum.values
                   |] -> do
                let enumLookup = zip values $ map (\ i -> [xMake| value.literal := [Prim (I i)] |] ) [1..]
                lift $ forM_ enumLookup $ \ (a,b) -> case a of
                    [xMatch| [Prim (S nm)] := reference |] -> addReference nm b
                    _ -> return ()
                tell [ ( [xMake| reference := [Prim (S name)] |]
                       , [xMake| reference := [Prim (S $ name `mappend` "_fromEnum")] |]
                       )
                     ]
                tell enumLookup
                let enumCount = genericLength values
                let lb = [eMake| 1 |]
                let ub = [xMake| value.literal := [Prim (I enumCount)] |]
                let newDom = [xMake| domain.int.ranges.range.fromTo := [lb,ub] |]
                let newDecl = [xMake| topLevel.letting.name.reference := [Prim (S $ name `mappend` "_fromEnum")]
                                    | topLevel.letting.domain         := [newDom]
                                    |]
                lift $ mkLog "handleEnums" $ vcat [ pretty statement
                                                  , "~~>"
                                                  , pretty newDecl
                                                  ]
                return [newDecl]
            _ -> return [statement]

doReplacements :: (Spec, [(E, E)]) -> Spec
doReplacements (Spec v s, mapping) = Spec v $ replaceAll mapping s

-- update those givens and finds whose domain refers to used-to-be-enums
updateGivenFinds :: MonadConjure m => Spec -> m Spec
updateGivenFinds spec = runIdentityT $ flip foreachStatement spec $ \ statement ->
    case statement of
        [xMatch| [declName] := topLevel.declaration.find.name
               | enumRanges := topLevel.declaration.find.domain.domain.enum.ranges
               |] -> do
            let newDom  = [xMake| domain.int.ranges := enumRanges |]
            let newDecl = [xMake| topLevel.declaration.find.name   := [declName]
                                | topLevel.declaration.find.domain := [newDom]
                                |]
            return [newDecl]
        [xMatch| [declName] := topLevel.declaration.given.name
               | enumRanges := topLevel.declaration.given.domain.domain.enum.ranges
               |] -> do
            let newDom  = [xMake| domain.int.ranges := enumRanges |]
            let newDecl = [xMake| topLevel.declaration.given.name   := [declName]
                                | topLevel.declaration.given.domain := [newDom]
                                |]
            return [newDecl]
        _ -> return [statement]

-- replaces given e new type enum
-- with     given e_fromEnumSize : int(1..)
--          letting e_fromEnum be domain int(1..e_fromEnumSize)
-- returns ( the new spec
--         , (old E , new E)
--         )
handleEnumsGiven :: MonadConjure m => Spec -> m (Spec, [(E, E)])
handleEnumsGiven spec
    = runWriterT
    $ flip foreachStatement spec $ \ statement ->
        case statement of
            [xMatch| [Prim (S name)] := topLevel.declaration.given.name.reference
                   | []              := topLevel.declaration.given.typeEnum
                   |] -> do
                tell [ ( [xMake| reference := [Prim (S name)] |]
                       , [xMake| reference := [Prim (S $ name `mappend` "_fromEnum")] |]
                       )
                     ]
                let enumCount = [xMake| reference := [Prim (S $ name `mappend` "_fromEnumSize")] |]
                let lb = [eMake| 1 |]
                let ub = enumCount

                let newDom1  = [xMake| domain.int.ranges.range.from := [lb] |]
                let newDecl1 = [xMake| topLevel.declaration.given.name.reference := [Prim (S $ name `mappend` "_fromEnumSize")]
                                     | topLevel.declaration.given.domain         := [newDom1]
                                     |]

                let newDom2  = [xMake| domain.int.ranges.range.fromTo := [lb,ub] |]
                let newDecl2 = [xMake| topLevel.letting.name.reference := [Prim (S $ name `mappend` "_fromEnum")]
                                     | topLevel.letting.domain         := [newDom2]
                                     |]
                lift $ mkLog "handleEnums" $ vcat [ pretty statement
                                                  , "~~>"
                                                  , pretty newDecl1
                                                  , pretty newDecl2
                                                  ]
                return [newDecl1,newDecl2]
            _ -> return [statement]



-- for each     given e new domain int
-- adds a       given e_size : int(0..)
-- returns      the new spec
handleGivenIntDom :: MonadConjure m => Spec -> m Spec
handleGivenIntDom spec
    = withBindingScope'
    $ flip evalStateT []
    $ flip foreachStatement spec $ \ statement ->
        case statement of
            [xMatch| [Prim (S name)] := topLevel.declaration.given.name.reference
                   | []              := topLevel.declaration.given.typeInt
                   |] -> do
                let lb = [eMake| 1 |]
                let newName = name `mappend` "_size"
                let newDom  = [xMake| domain.int.ranges.range.from := [lb] |]
                let newDecl = [xMake| topLevel.declaration.given.name.reference := [Prim (S newName)]
                                    | topLevel.declaration.given.domain         := [newDom]
                                    |]
                befores <- get
                -- only add this new given if this is the first time we are seeing it.
                if statement `elem` befores || newDecl `elem` befores
                    then do
                        lift $ mkLog "debug"
                             $ vcat [ "not adding"
                                    , pretty statement
                                    ]
                        return [statement]
                    else do
                        lift $ mkLog "handleGivenIntDom"
                             $ vcat [ pretty statement
                                    , "~~>"
                                    , pretty newDecl
                                    ]
                        modify ([newDecl, statement] ++) -- add these statements as seen.
                        return [newDecl, statement]
            _ -> do
                modify (statement :)
                return [statement]


