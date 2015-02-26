{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ParallelListComp #-}

module Conjure.Representations.Variant
    ( variant
    ) where

-- conjure
import Conjure.Prelude
import Conjure.Language.Definition
import Conjure.Language.Domain
import Conjure.Language.Pretty
import Conjure.Language.TH
import Conjure.Representations.Internal


variant :: forall m . MonadFail m => Representation m
variant = Representation chck downD structuralCons downC up

    where

        chck :: TypeOf_ReprCheck m
        chck f (DomainVariant ds) =
            let names = map fst ds
                outDoms = mapM (f . snd) ds
            in  [ DomainVariant (zip names ds') | ds' <- outDoms ]
        chck _ _ = []

        mkName name n = mconcat [name, "_", n]

        downD :: TypeOf_DownD m
        downD (name, DomainVariant ds) = return $ Just
            $ (mkName name "_tag", defRepr $ mkDomainIntB 1 (fromInt (genericLength ds)))
            : [ (mkName name n, d)
              | (n,d) <- ds
              ]
        downD _ = na "{downD}"

        structuralCons :: TypeOf_Structural m
        structuralCons f downX1 (DomainVariant ds) = do
            let
                innerStructuralCons fresh which thisIndex thisRef thisDom = do
                    let activeZone b = [essence| &which = &thisIndex -> &b |]
                    -- preparing structural constraints for the inner guys
                    innerStructuralConsGen <- f thisDom
                    outs <- innerStructuralConsGen fresh thisRef
                    return (map activeZone outs)

                dontCares which thisIndex thisRef =
                    [essence| &which != &thisIndex -> dontCare(&thisRef) |]

            return $ \ fresh rec -> do
                (which:refs) <- downX1 rec
                (sort . concat) <$> sequence
                    [ do
                        isc <- innerStructuralCons fresh which (fromInt i) ref dom
                        let dcs = dontCares              which (fromInt i) ref
                        return (dcs:isc)
                    | (i, ref, (_, dom)) <- zip3 [1..] refs ds
                    ]
        structuralCons _ _ _ = na "{structuralCons} variant"

        -- TODO: check if (length ds == length cs)
        downC :: TypeOf_DownC m
        downC (name, DomainVariant ds, ConstantAbstract (AbsLitVariant _ n c))
            | Just d <- lookup n ds = return $ Just
                [(mkName name n, d, c)]
        downC _ = na "{downC}"

        up :: TypeOf_Up m
        up ctxt (name, DomainVariant ds) = do
            let dsForgotten = [ (n, defRepr d) | (n,d) <- ds ]
            case lookup (mkName name "_tag") ctxt of
                Just (ConstantInt i) ->
                    let iTag = at ds (fromInteger (i-1)) |> fst
                        iName = mkName name iTag
                    in  case lookup iName ctxt of
                            Just val -> return (name, ConstantAbstract $ AbsLitVariant (Just dsForgotten) iTag val)
                            Nothing -> fail $ vcat $
                                [ "No value for:" <+> pretty iName
                                , "When working on:" <+> pretty name
                                , "With domain:" <+> pretty (DomainRecord ds)
                                ] ++
                                ("Bindings in context:" : prettyContext ctxt)
                Nothing -> fail $ vcat $
                    [ "No value for:" <+> pretty (mkName name "_tag")
                    , "When working on:" <+> pretty name
                    , "With domain:" <+> pretty (DomainRecord ds)
                    ] ++
                    ("Bindings in context:" : prettyContext ctxt)
                Just val -> fail $ vcat $
                    [ "Expecting an integer value for:" <+> pretty (mkName name "_tag")
                    , "When working on:" <+> pretty name
                    , "With domain:" <+> pretty (DomainRecord ds)
                    , "But got:" <+> pretty val
                    ] ++
                    ("Bindings in context:" : prettyContext ctxt)
        up _ _ = na "{up}"

