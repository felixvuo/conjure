{-# LANGUAGE DeriveDataTypeable #-}
{-# OPTIONS_GHC -fno-cse #-} -- stupid cmdargs

module Conjure.UI where

-- conjure
import Conjure.Prelude
import Conjure.RepositoryVersion ( repositoryVersion )

-- cmdargs
import System.Console.CmdArgs hiding ( Default(..) )


data UI
    = Modelling
        { essence                   :: FilePath       -- essence, mandatory
        -- flags related to output
        , outputDirectory           :: FilePath
        , numberingStart            :: Int
        , smartFilenames            :: Bool
        -- flags related to logging
        , logLevel                  :: LogLevel
        , verboseTrail              :: Bool
        , logRuleFails              :: Bool
        , logRuleSuccesses          :: Bool
        , logRuleAttempts           :: Bool
        -- flags related to modelling decisions
        , strategyQ                 :: String
        , strategyA                 :: String
        , channelling               :: Bool
        , parameterRepresentation   :: Bool
        , seed                      :: Maybe Int
        , limitModels               :: Maybe Int
        , limitTime                 :: Maybe Int
        }
    | RefineParam
        { eprime           :: FilePath       -- eprime, mandatory
        , essenceParam     :: FilePath       -- essence-param, mandatory
        , eprimeParam      :: Maybe FilePath -- eprime-param, optional, by default (essenceParam <-.> "eprime-param")
        , logLevel         :: LogLevel
        , limitTime        :: Maybe Int
        }
    | TranslateSolution
        { eprime           :: FilePath       -- eprime, mandatory
        , essenceParamO    :: Maybe FilePath -- essence-param, optional
        , eprimeSolution   :: FilePath       -- eprime-solution, mandatory
        , essenceSolutionO :: Maybe FilePath -- essence-solution, optional, by default (eprimeSolution <-.> "solution")
        , logLevel         :: LogLevel
        , limitTime        :: Maybe Int
        }
    | ValidateSolution
        { essence          :: FilePath       -- essence, mandatory
        , essenceParamO    :: Maybe FilePath -- essence-param, optional
        , essenceSolution  :: FilePath       -- essence-solution, mandatory, by default (eprimeSolution <-.> "solution")
        , logLevel         :: LogLevel
        , limitTime        :: Maybe Int
        }
    | Diff
        { file1    :: FilePath
        , file2    :: FilePath
        , logLevel :: LogLevel
        , limitTime        :: Maybe Int
        }
    | TypeCheck
        { essence  :: FilePath
        , logLevel :: LogLevel
        , limitTime        :: Maybe Int
        }
    deriving (Eq, Ord, Show, Data, Typeable)


ui :: UI
ui = modes
    [ Modelling
        { essence          = def   &= typ "ESSENCE_FILE"
                                   &= argPos 0
        , outputDirectory  = "conjure-output"
                                   &= typDir
                                   &= name "output-directory"
                                   &= name "o"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Output directory. Generated models will be saved here.\n\
                                           \Default value: 'conjure-output'"
        , numberingStart   = 1     &= name "numbering-start"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Starting value to output files.\n\
                                           \Default value: 1"
        , smartFilenames   = False &= name "smart-filenames"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Use \"smart names\" for the models.\n\
                                           \Turned off by default.\n\
                                           \Caution: With this flag, Conjure will use the answers when producing \
                                           \a filename. It will ignore the order of questions. \
                                           \This will become a problem if anything other than 'f' is used for questions."
        , logLevel         = def   &= name "log-level"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Log level."
        , verboseTrail     = False &= name "verbose-trail"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Whether to generate verbose trails or not."
        , logRuleFails     = False &= name "log-rule-fails"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Generate logs for rule failures. (Caution: can be a lot!)"
        , logRuleSuccesses = False &= name "log-rule-successes"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Generate logs for rule applications."
        , logRuleAttempts  = False &= name "log-rule-attempts"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Generate logs for rule attempts. (Caution: can be a lot!)"
        , strategyQ        = "f"   &= typ "STRATEGY"
                                   &= name "strategy-q"
                                   &= name "q"
                                   &= groupname "Model generation"
                                   &= explicit
                                   &= help "Strategy to use when selecting the next question to answer. \
                                           \Options: f (for first), i (for interactive), r (for random), x (for all). \
                                           \The letter a (for auto) can be prepended to automatically skip \
                                           \when there is only one option at any point.\n\
                                           \Default value: f"
        , strategyA        = "ai"  &= typ "STRATEGY"
                                   &= name "strategy-a"
                                   &= name "a"
                                   &= groupname "Model generation"
                                   &= explicit
                                   &= help "Strategy to use when selecting an answer. Same options as strategy-q.\n\
                                           \Moreover, c (for compact) can be used to pick the most 'compact' option \
                                           \at every decision point.\n\
                                           \Default value: ai"
        , channelling = True       &= name "channelling"
                                   &= groupname "Model generation"
                                   &= explicit
                                   &= help "Whether to produce channelled models or not.\n\
                                           \Can be true or false. (true by default)\n\
                                           \    false: Do not produce channelled models.\n\
                                           \    true : Produce channelled models."
        , parameterRepresentation = False
                                   &= name "parameter-representation"
                                   &= groupname "Model generation"
                                   &= explicit
                                   &= help "Representation selection for abstract parameters.\n\
                                           \Can be true or false. (false by default)\n\
                                           \    false: Select a single representation.\n\
                                           \    true : Select multiple representations."
        , seed = Nothing           &= name "seed"
                                   &= groupname "Model generation"
                                   &= explicit
                                   &= help "The seed for the random number generator."
        , limitModels = Nothing    &= name "limit-models"
                                   &= groupname "Model generation"
                                   &= explicit
                                   &= help "Maximum number of models to generate."
        , limitTime = Nothing      &= name "limit-time"
                                   &= groupname "Model generation"
                                   &= explicit
                                   &= help "Time limit in seconds. (CPU time)."
        }                          &= name "modelling"
                                   &= explicit
                                   &= help "The main act. Given a problem specification in Essence, \
                                           \produce constraint programming models in Essence'."
                                   &= auto
    , RefineParam
        { eprime           = def   &= typFile
                                   &= name "eprime"
                                   &= explicit
                                   &= help "An Essence' model generated by Conjure."
        , essenceParam     = def   &= typFile
                                   &= name "essence-param"
                                   &= explicit
                                   &= help "An Essence parameter for the original problem specification."
        , eprimeParam      = def   &= typFile
                                   &= name "eprime-param"
                                   &= explicit
                                   &= help "An Essence' parameter matching the Essence' model.\n\
                                           \This field is optional.\n\
                                           \By default, its value will be 'foo.eprime-param'\n\
                                           \if the Essence parameter file is named 'foo.param'"
        , logLevel         = def   &= name "log-level"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Log level."
        , limitTime = Nothing      &= name "limit-time"
                                   &= explicit
                                   &= help "Time limit in seconds. (CPU time)."
        }                          &= name "refine-param"
                                   &= explicit
                                   &= help "Refinement of parameter files written in Essence for a \
                                           \particular Essence' model.\n\
                                           \The model needs to be generated by Conjure."
    , TranslateSolution
        { eprime           = def   &= typFile
                                   &= name "eprime"
                                   &= explicit
                                   &= help "An Essence' model generated by Conjure."
        , essenceParamO    = def   &= typFile
                                   &= name "essence-param"
                                   &= explicit
                                   &= help "An Essence parameter for the original problem specification.\n\
                                           \This field is optional."
        , eprimeSolution   = def   &= typFile
                                   &= name "eprime-solution"
                                   &= explicit
                                   &= help "An Essence' solution for the corresponding Essence' model."
        , essenceSolutionO = def   &= typFile
                                   &= name "essence-solution"
                                   &= explicit
                                   &= help "An Essence solution for the original problem specification.\n\
                                           \This field is optional.\n\
                                           \By default, its value will be the value of --eprime-solution, \
                                           \with all extensions dropped the extension '.solution' is added instead."
        , logLevel         = def   &= name "log-level"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Log level."
        , limitTime = Nothing      &= name "limit-time"
                                   &= explicit
                                   &= help "Time limit in seconds. (CPU time)."
        }                          &= name "translate-solution"
                                   &= explicit
                                   &= help "Translation of solutions back to Essence."
    , ValidateSolution
        { essence          = def   &= typFile
                                   &= name "essence"
                                   &= explicit
                                   &= help "A problem specification in Essence"
        , essenceParamO    = def   &= typFile
                                   &= name "param"
                                   &= explicit
                                   &= help "An Essence parameter.\n\
                                           \This field is optional."
        , essenceSolution  = def   &= typFile
                                   &= name "solution"
                                   &= explicit
                                   &= help "An Essence solution."
        , logLevel         = def   &= name "log-level"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Log level."
        , limitTime = Nothing      &= name "limit-time"
                                   &= explicit
                                   &= help "Time limit in seconds. (CPU time)."
        }                          &= name "validate-solution"
                                   &= explicit
                                   &= help "Validating a solution."
    , Diff
        { file1 = def              &= typFile
                                   &= argPos 0
        , file2 = def              &= typFile
                                   &= argPos 1
        , logLevel         = def   &= name "log-level"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Log level."
        , limitTime = Nothing      &= name "limit-time"
                                   &= explicit
                                   &= help "Time limit in seconds. (CPU time)."
        }                          &= name "diff"
                                   &= explicit
                                   &= help "Diff on two Essence files. Works on models, parameters, and solutions."
    , TypeCheck
        { essence          = def   &= typ "ESSENCE_FILE"
                                   &= argPos 0
        , logLevel         = def   &= name "log-level"
                                   &= groupname "Logging & Output"
                                   &= explicit
                                   &= help "Log level."
        , limitTime = Nothing      &= name "limit-time"
                                   &= explicit
                                   &= help "Time limit in seconds. (CPU time)."
        }                          &= name "type-check"
                                   &= explicit
                                   &= help "Type-checking a single Essence file."
    ]                              &= program "conjure"
                                   &= summary ("Conjure, the automated constraint modelling tool.\n\
                                               \Version: " ++ repositoryVersion)
