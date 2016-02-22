module Conjure.Process.FiniteGivens
    ( finiteGivens
    , finiteGivensParam
    ) where

import Conjure.Prelude
import Conjure.Bug
import Conjure.UserError
import Conjure.Language.Definition
import Conjure.Language.Constant
import Conjure.Language.Domain
import Conjure.Language.Pretty
import Conjure.Language.Instantiate ( instantiateExpression )
import Conjure.Process.Enumerate ( EnumerateDomain )


-- | givens should have finite domains. except ints.
--   this transformation introduces extra given ints to make them finite.
--   the values for the extra givens will be computed during translate-solution
finiteGivens
    :: (MonadFail m, MonadLog m, NameGen m)
    => Model
    -> m Model
finiteGivens m = flip evalStateT 1 $ do
    statements <- forM (mStatements m) $ \ st ->
        case st of
            Declaration (FindOrGiven Given name domain) -> do
                (domain', extras, _) <- mkFinite domain
                return $ [ Declaration $ FindOrGiven Given e (DomainInt []) | e <- extras ]
                      ++ [ Declaration $ FindOrGiven Given name domain'                   ]
            _ -> return [st]
    return m { mStatements = concat statements }


finiteGivensParam
    :: (MonadFail m, MonadUserError m, MonadLog m, NameGen m, EnumerateDomain m)
    => Model                                -- eprime
    -> Model                                -- essence-param
    -> m (Model, [Name])                    -- essence-param
finiteGivensParam eprimeModel essenceParam = flip evalStateT 1 $ do
    let essenceGivenNames = eprimeModel |> mInfo |> miGivens
    let essenceGivens     = eprimeModel |> mInfo |> miOriginalDomains
    let essenceLettings   = extractLettings essenceParam
    extras <- forM essenceGivenNames $ \ name -> do
        logDebugVerbose $ "finiteGivensParam name" <+> pretty name
        case (lookup name essenceGivens, lookup name essenceLettings) of
            (Nothing, _) -> bug $ "Not found:" <+> pretty name
            (_, Nothing) -> return []
            (Just domain, Just expr) -> do
                logDebugVerbose $ "finiteGivensParam domain  " <+> pretty domain
                logDebugVerbose $ "finiteGivensParam expr    " <+> pretty expr
                constant <- instantiateExpression [] expr
                logDebugVerbose $ "finiteGivensParam constant" <+> pretty constant
                (_, _, f) <- mkFinite domain
                outs <- f constant
                logDebugVerbose $ "finiteGivensParam outs    " <+> vcat (map pretty outs)
                return outs
    return
        ( essenceParam
            { mStatements = [ Declaration (Letting n (Constant c)) | (n,c) <- concat extras ]
                         ++ mStatements essenceParam
            }
        , map fst (concat extras)
        )


-- | given a domain, add it additional attributes to make it _smaller_
--   for example, this means adding a size attribute at the outer-most level
--   and adding a maxSize attribute at the inner levels.
mkFinite
    :: (MonadState Int m, MonadFail m, NameGen m, MonadLog m)
    => Domain () Expression
    -> m ( Domain () Expression                 -- "finite" domain
         , [Name]                               -- extra givens
         , Constant -> m [(Name, Constant)]     -- value calculator for the extra givens
                                                -- input is a list of values for the domain
         )
mkFinite d@DomainTuple{}     = mkFiniteOutermost d
mkFinite d@DomainMatrix{}    = mkFiniteOutermost d
mkFinite d@DomainSet{}       = mkFiniteOutermost d
mkFinite d@DomainSequence{}  = mkFiniteOutermost d
mkFinite d@DomainFunction{}  = mkFiniteOutermost d
mkFinite d@DomainRelation{}  = mkFiniteOutermost d
mkFinite d@DomainPartition{} = mkFiniteOutermost d
mkFinite d = return (d, [], const (return []))


mkFiniteOutermost
    :: (MonadState Int m, MonadFail m, NameGen m, MonadLog m)
    => Domain () Expression
    -> m ( Domain () Expression
         , [Name]
         , Constant -> m [(Name, Constant)]
         )
mkFiniteOutermost (DomainTuple inners) = do
    mids <- mapM mkFiniteInner inners
    return
        ( DomainTuple (map fst3 mids)
        , concatMap snd3 mids
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainTuple" <+> pretty constant
                xs <- viewConstantTuple constant
                let innerFs = map thd3 mids
                innerValues <- sequence [ innerF [x] | (innerF, x) <- zip innerFs xs ]
                return (concat innerValues)
        )
mkFiniteOutermost (DomainMatrix index inner) = do
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainMatrix index inner'
        , innerExtras
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainMatrix" <+> pretty constant
                (_, matr) <- viewConstantMatrix constant
                innerValues <- innerF matr
                return innerValues
        )
mkFiniteOutermost (DomainSet () attr@(SetAttr SizeAttr_Size{}) inner) = do
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainSet () attr inner'
        , innerExtras
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainSet" <+> pretty constant
                set <- viewConstantSet constant
                innerValues <- innerF set
                return innerValues
        )
mkFiniteOutermost (DomainSet () _ inner) = do
    s <- nextName "fin"
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainSet () (SetAttr (SizeAttr_Size (fromName s))) inner'
        , s:innerExtras
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainSet" <+> pretty constant
                set <- viewConstantSet constant
                let setSize = genericLength $ nub set
                innerValues <- innerF set
                return $ innerValues ++ [(s, ConstantInt setSize)]
        )
mkFiniteOutermost (DomainSequence () attr@(SequenceAttr SizeAttr_Size{} _) inner) = do
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainSequence () attr inner'
        , innerExtras
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainSequence" <+> pretty constant
                set <- viewConstantSequence constant
                innerValues <- innerF set
                return innerValues
        )
mkFiniteOutermost (DomainSequence () (SequenceAttr _ jectivityAttr) inner) = do
    s <- nextName "fin"
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainSequence () (SequenceAttr (SizeAttr_Size (fromName s)) jectivityAttr) inner'
        , s:innerExtras
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainSequence" <+> pretty constant
                set <- viewConstantSequence constant
                let setSize = genericLength $ nub set
                innerValues <- innerF set
                return $ innerValues ++ [(s, ConstantInt setSize)]
        )
mkFiniteOutermost (DomainFunction () attr@(FunctionAttr SizeAttr_Size{} _ _) innerFr innerTo) = do
    (innerFr', innerFrExtras, innerFrF) <- mkFiniteInner innerFr
    (innerTo', innerToExtras, innerToF) <- mkFiniteInner innerTo
    return
        ( DomainFunction () attr innerFr' innerTo'
        , innerFrExtras ++ innerToExtras
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainFunction" <+> pretty constant
                function <- viewConstantFunction constant
                innerFrValues <- innerFrF (map fst function)
                innerToValues <- innerToF (map snd function)
                return $ innerFrValues ++ innerToValues
        )
mkFiniteOutermost (DomainFunction () (FunctionAttr _ partialityAttr jectivityAttr) innerFr innerTo) = do
    s <- nextName "fin"
    (innerFr', innerFrExtras, innerFrF) <- mkFiniteInner innerFr
    (innerTo', innerToExtras, innerToF) <- mkFiniteInner innerTo
    return
        ( DomainFunction ()
                (FunctionAttr (SizeAttr_Size (fromName s)) partialityAttr jectivityAttr)
                innerFr' innerTo'
        , s : innerFrExtras ++ innerToExtras
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainFunction" <+> pretty constant
                function <- viewConstantFunction constant
                let functionSize = genericLength $ nub function
                innerFrValues <- innerFrF (map fst function)
                innerToValues <- innerToF (map snd function)
                return $ innerFrValues ++ innerToValues ++ [(s, ConstantInt functionSize)]
        )
mkFiniteOutermost (DomainRelation () attr@(RelationAttr SizeAttr_Size{} _) inners) = do
    (inners', innersExtras, innersF) <- unzip3 <$> mapM mkFiniteInner inners
    return
        ( DomainRelation () attr inners'
        , concat innersExtras
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainRelation" <+> pretty constant
                relation <- viewConstantRelation constant
                innersValues <- zipWithM ($) innersF (transpose relation)
                return (concat innersValues)
        )
mkFiniteOutermost (DomainRelation () (RelationAttr _ binRelAttr) inners) = do
    s <- nextName "fin"
    (inners', innersExtras, innersF) <- unzip3 <$> mapM mkFiniteInner inners
    return
        ( DomainRelation ()
                (RelationAttr (SizeAttr_Size (fromName s)) binRelAttr)
                inners'
        , s : concat innersExtras
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainRelation" <+> pretty constant
                relation <- viewConstantRelation constant
                let relationSize = genericLength $ nub relation
                innersValues <- zipWithM ($) innersF (transpose relation)
                return $ concat innersValues ++ [(s, ConstantInt relationSize)]
        )
mkFiniteOutermost (DomainPartition () attr@(PartitionAttr SizeAttr_Size{} _ _) inner) = do
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainPartition () attr inner'
        , innerExtras
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainPartition" <+> pretty constant
                parts <- viewConstantPartition constant
                -- innerValues <- mapM innerF (parts :: ())
                -- innerValues <- mapM (innerF :: ()) parts
                innerValues <- mapM innerF parts
                return (concat innerValues)
        )
mkFiniteOutermost (DomainPartition () (PartitionAttr _ partsSizeAttr isRegularAttr) inner) = do
    s <- nextName "fin"
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainPartition () (PartitionAttr (SizeAttr_Size (fromName s)) partsSizeAttr isRegularAttr) inner'
        , s:innerExtras
        , \ constant -> do
                logDebug $ "mkFiniteOutermost DomainPartition" <+> pretty constant
                parts <- viewConstantPartition constant
                let partsNumVal = genericLength $ nub parts
                innerValues <- mapM innerF parts
                return $ concat innerValues ++ [(s, ConstantInt partsNumVal)]
        )
mkFiniteOutermost d = return (d, [], const (return []))


mkFiniteInner
    :: (MonadState Int m, MonadFail m, NameGen m, MonadLog m)
    => Domain () Expression
    -> m ( Domain () Expression
         , [Name]
         , [Constant] -> m [(Name, Constant)]
         )
mkFiniteInner (DomainInt []) = do
    fr <- nextName "fin"
    to <- nextName "fin"
    return
        ( DomainInt [RangeBounded (fromName fr) (fromName to)]
        , [fr, to]
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainInt" <+> vcat (map pretty constants)
                ints <- mapM viewConstantInt constants
                return [ (fr, ConstantInt (minimum ints))
                       , (to, ConstantInt (maximum ints))
                       ]
        )
mkFiniteInner (DomainInt [RangeLowerBounded low]) = do
    new <- nextName "fin"
    return
        ( DomainInt [RangeBounded low (fromName new)]
        , [new]
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainInt" <+> vcat (map pretty constants)
                ints <- mapM viewConstantInt constants
                return [ (new, ConstantInt (maximum ints)) ]
        )
mkFiniteInner (DomainInt [RangeUpperBounded upp]) = do
    new <- nextName "fin"
    return
        ( DomainInt [RangeBounded (fromName new) upp]
        , [new]
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainInt" <+> vcat (map pretty constants)
                ints <- mapM viewConstantInt constants
                return [ (new, ConstantInt (minimum ints)) ]
        )
mkFiniteInner (DomainTuple inners) = do
    mids <- mapM mkFiniteInner inners
    return
        ( DomainTuple (map fst3 mids)
        , concatMap snd3 mids
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainTuple" <+> vcat (map pretty constants)
                xss <- mapM viewConstantTuple constants
                let innerFs = map thd3 mids
                innerValues <- sequence [ innerF xs | (innerF, xs) <- zip innerFs xss ]
                return (concat innerValues)
        )
mkFiniteInner (DomainMatrix index inner) = do
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainMatrix index inner'
        , innerExtras
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainMatrix" <+> vcat (map pretty constants)
                xss <- mapM viewConstantMatrix constants
                innerF (concatMap snd xss)
        )
mkFiniteInner (DomainSet () attr@(SetAttr SizeAttr_Size{}) inner) = do
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainSet () attr inner'
        , innerExtras
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainSet" <+> vcat (map pretty constants)
                sets <- mapM viewConstantSet constants
                innerF (concat sets)
        )
mkFiniteInner (DomainSet () _ inner) = do
    s <- nextName "fin"
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainSet () (SetAttr (SizeAttr_MaxSize (fromName s))) inner'
        , s:innerExtras
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainSet" <+> vcat (map pretty constants)
                sets <- mapM viewConstantSet constants
                let setMaxSize = maximum $ map (genericLength . nub) sets
                innerValues <- innerF (concat sets)
                return $ innerValues ++ [(s, ConstantInt setMaxSize)]
        )
mkFiniteInner (DomainSequence () attr@(SequenceAttr SizeAttr_Size{} _) inner) = do
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainSequence () attr inner'
        , innerExtras
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainSequence" <+> vcat (map pretty constants)
                seqs <- mapM viewConstantSequence constants
                innerF (concat seqs)
        )
mkFiniteInner (DomainSequence () (SequenceAttr _ jectivityAttr) inner) = do
    s <- nextName "fin"
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainSequence () (SequenceAttr (SizeAttr_MaxSize (fromName s)) jectivityAttr) inner'
        , s:innerExtras
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainSequence" <+> vcat (map pretty constants)
                seqs <- mapM viewConstantSequence constants
                let seqMaxSize = maximum $ map genericLength seqs
                innerValues <- innerF (concat seqs)
                return $ innerValues ++ [(s, ConstantInt seqMaxSize)]
        )
mkFiniteInner (DomainFunction () attr@(FunctionAttr SizeAttr_Size{} _ _) innerFr innerTo) = do
    (innerFr', innerFrExtras, innerFrF) <- mkFiniteInner innerFr
    (innerTo', innerToExtras, innerToF) <- mkFiniteInner innerTo
    return
        ( DomainFunction () attr innerFr' innerTo'
        , innerFrExtras ++ innerToExtras
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainFunction" <+> vcat (map pretty constants)
                functions <- mapM viewConstantFunction constants
                innerFrValues <- innerFrF (map fst (concat functions))
                innerToValues <- innerToF (map snd (concat functions))
                return $ innerFrValues ++ innerToValues
        )
mkFiniteInner (DomainFunction () (FunctionAttr _ partialityAttr jectivityAttr) innerFr innerTo) = do
    s <- nextName "fin"
    (innerFr', innerFrExtras, innerFrF) <- mkFiniteInner innerFr
    (innerTo', innerToExtras, innerToF) <- mkFiniteInner innerTo
    return
        ( DomainFunction ()
                (FunctionAttr (SizeAttr_MaxSize (fromName s)) partialityAttr jectivityAttr)
                innerFr' innerTo'
        , s : innerFrExtras ++ innerToExtras
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainFunction" <+> vcat (map pretty constants)
                functions <- mapM viewConstantFunction constants
                let functionMaxSize = maximum $ map (genericLength . nub) functions
                innerFrValues <- innerFrF (map fst (concat functions))
                innerToValues <- innerToF (map snd (concat functions))
                return $ innerFrValues ++ innerToValues ++ [(s, ConstantInt functionMaxSize)]
        )
mkFiniteInner (DomainRelation () attr@(RelationAttr SizeAttr_Size{} _) inners) = do
    (inners', innersExtras, innersF) <- unzip3 <$> mapM mkFiniteInner inners
    return
        ( DomainRelation () attr inners'
        , concat innersExtras
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainRelation" <+> vcat (map pretty constants)
                relations <- mapM viewConstantRelation constants
                innersValues <- zipWithM ($) innersF (transpose $ concat relations)
                return $ concat innersValues
        )
mkFiniteInner (DomainRelation () (RelationAttr _ binRelAttr) inners) = do
    s <- nextName "fin"
    (inners', innersExtras, innersF) <- unzip3 <$> mapM mkFiniteInner inners
    return
        ( DomainRelation ()
                (RelationAttr (SizeAttr_MaxSize (fromName s)) binRelAttr)
                inners'
        , s : concat innersExtras
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainRelation" <+> vcat (map pretty constants)
                relations <- mapM viewConstantRelation constants
                let relationMaxSize = maximum $ map (genericLength . nub) relations
                innersValues <- zipWithM ($) innersF (transpose $ concat relations)
                return $ concat innersValues ++ [(s, ConstantInt relationMaxSize)]
        )
mkFiniteInner (DomainPartition () attr@(PartitionAttr SizeAttr_Size{} _ _) inner) = do
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainPartition () attr inner'
        , innerExtras
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainPartition" <+> vcat (map pretty constants)
                parts <- mapM viewConstantPartition constants
                innersValues <- mapM innerF (concat parts)
                return $ concat innersValues
        )
mkFiniteInner (DomainPartition () (PartitionAttr _ partsSizeAttr isRegularAttr) inner) = do
    s <- nextName "fin"
    (inner', innerExtras, innerF) <- mkFiniteInner inner
    return
        ( DomainPartition () (PartitionAttr (SizeAttr_MaxSize (fromName s)) partsSizeAttr isRegularAttr) inner'
        , s:innerExtras
        , \ constants -> do
                logDebug $ "mkFiniteInner DomainPartition" <+> vcat (map pretty constants)
                parts <- mapM viewConstantPartition constants
                let partsNumVal = maximum $ map (genericLength . nub) parts
                innerValues <- mapM innerF (concat parts)
                return $ concat innerValues ++ [(s, ConstantInt partsNumVal)]
        )
mkFiniteInner d = return (d, [], const (return []))
