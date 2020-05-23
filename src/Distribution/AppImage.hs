{-|
Module:    Distribution.AppImage
Copyright: 2020 Gabriele Sales

This module provides a custom build hook that automatically wraps executables
inside AppImage bundles.

Internally, it calls the @appimagetool@ and @linuxdeploy@ utilities which must
be already installed on the system.
-}

{-# LANGUAGE RecordWildCards #-}

module Distribution.AppImage
  ( AppImage(..)
  , appImageBuildHook
  )
where

import           Control.Monad
import           Data.String
import           Distribution.PackageDescription
import           Distribution.Simple
import           Distribution.Simple.LocalBuildInfo
import           Distribution.Simple.Program
import           Distribution.Simple.Program.Types
import           Distribution.Simple.Setup
import           Distribution.Simple.Utils
import           Distribution.System
import           Distribution.Verbosity
import           System.FilePath


data AppImage = AppImage {
  -- | Application name. The AppImage bundle will be produced in
  -- @dist\/build\//appName/.AppImage@ and will contain the executable
  -- /appName/.
  appName      :: String,
  -- | Path to desktop file.
  appDesktop   :: FilePath,
  -- | Application icons.
  appIcons     :: [FilePath],
  -- | Other resources to bundle. Stored in the @\usr\/share\//appName/@
  -- directory inside the image.
  appResources :: [FilePath]
  } deriving (Eq, Show)


-- | Hook for building AppImage bundles. Does nothing if the OS is not Linux.
--
-- Use this function as a @postBuild@ hook.
appImageBuildHook
  :: [AppImage] -- ^ Applications to build.
  -> Args       -- ^ Other parameters as defined in 'Distribution.Simple.postBuild'.
  -> BuildFlags
  -> PackageDescription
  -> LocalBuildInfo
  -> IO ()
appImageBuildHook apps args flags pkg buildInfo =
  when (buildOS == Linux) $
    mapM_ (makeBundle args flags pkg buildInfo) apps

makeBundle :: Args -> BuildFlags -> PackageDescription -> LocalBuildInfo -> AppImage -> IO ()
makeBundle args flags pkg buildInfo app@AppImage{..} = do
  let bdir = buildDir buildInfo
      verb = fromFlagOrDefault normal (buildVerbosity flags)
  unless (hasExecutable pkg appName) $
    die' verb ("No executable defined for the AppImage bundle: " ++ appName)
  when (null appIcons) $
    die' verb ("No icon defined for the AppImage bundle: " ++ appName)
  withTempDirectory verb bdir "appimage." $ \appDir -> do
    deployExe (bdir </> appName </> appName) app appDir verb
    bundleFiles appResources (appDir </> "usr" </> "share" </> appName) verb
    bundleApp appDir verb

hasExecutable :: PackageDescription -> String -> Bool
hasExecutable pkg name =
  any (\e -> exeName e == fromString name) (executables pkg)

deployExe :: FilePath -> AppImage -> FilePath -> Verbosity -> IO ()
deployExe exe AppImage{..} appDir verb = do
  prog <- findProg "linuxdeploy" verb
  runProgram verb prog $
    [ "--appdir=" ++ appDir
    , "--executable=" ++ exe
    , "--desktop-file=" ++ appDesktop ] ++
    map ("--icon-file=" ++) appIcons

bundleFiles :: [FilePath] -> FilePath -> Verbosity -> IO ()
bundleFiles files dest verb = prepare >> mapM_ copy files
  where
    prepare = createDirectoryIfMissingVerbose verb True dest

    copy file = copyFileVerbose verb file (dest </> takeFileName file)

bundleApp :: FilePath -> Verbosity -> IO ()
bundleApp appDir verb = do
  prog <- findProg "appimagetool" verb
  let (wdir, name) = splitFileName appDir
  runProgramInvocation verb $
    (programInvocation prog [name]) { progInvokeCwd = Just wdir }

findProg :: String -> Verbosity -> IO ConfiguredProgram
findProg name verb = do
  found <- findProgramOnSearchPath verb defaultProgramSearchPath name
  case found of
    Nothing        -> die' verb ("Command " ++ name ++ " is not available")
    Just (path, _) -> return (simpleConfiguredProgram name (FoundOnSystem path))
