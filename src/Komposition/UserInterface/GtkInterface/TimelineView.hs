{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE ExplicitForAll    #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedLabels  #-}
{-# LANGUAGE OverloadedLists   #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The main view of Komposition's GTK interface.
module Komposition.UserInterface.GtkInterface.TimelineView
  ( timelineView
  )
where

import           Komposition.Prelude                                     hiding
                                                                          (on)

import           Control.Lens
import           Data.Int                                                (Int32)
import           Data.Text                                               (Text)
import           GI.Gtk                                                  (Align (..),
                                                                          Box (..),
                                                                          Button (..),
                                                                          Label (..),
                                                                          MenuBar (..),
                                                                          MenuItem (..),
                                                                          Orientation (..),
                                                                          PolicyType (..),
                                                                          ScrolledWindow (..),
                                                                          Window (..))
import           GI.Gtk.Declarative
import           GI.Pango                                                (EllipsizeMode (..))

import           Komposition.Composition
import           Komposition.Composition.Focused
import           Komposition.Composition.Paste                           (PastePosition (..))
import           Komposition.Duration
import           Komposition.Focus
import           Komposition.Library
import           Komposition.MediaType
import           Komposition.Project
import           Komposition.UserInterface                               hiding (Window,
                                                                          timelineView)
import           Komposition.UserInterface.GtkInterface.NumberInput      as NumberInput
import           Komposition.UserInterface.GtkInterface.RangeSlider
import           Komposition.UserInterface.GtkInterface.ThumbnailPreview
import           Komposition.VideoSpeed

widthFromDuration :: ZoomLevel -> Duration -> Int32
widthFromDuration (ZoomLevel zl) duration' =
  round (durationToSeconds duration' * 5 * zl)

focusedClass :: Focused -> Text
focusedClass = \case
  Focused             -> "focused"
  TransitivelyFocused -> "transitively-focused"
  Blurred             -> "blurred"

renderClipAsset
  :: AssetMetadataLens asset
  => HasDuration asset
  => ZoomLevel
  -> Focus SequenceFocusType
  -> Focused
  -> asset
  -> Duration
  -> Widget (Event TimelineMode)
renderClipAsset zl thisFocus focused asset' duration' = container
  Box
  [ classes ["clip", focusedClass focused]
  , #orientation := OrientationHorizontal
  , #tooltipText := toS (asset' ^. assetMetadata . path . unOriginalPath)
  ]
  [ boxChild False False 0 $ widget
      Button
      [ on #clicked (CommandKeyMappedEvent (JumpFocus thisFocus))
      , #widthRequest := widthFromDuration zl duration'
      , #hasFocus := (focused == Focused)
      ]
  ]

renderGap
  :: ZoomLevel
  -> (Focus SequenceFocusType, Focused)
  -> Duration
  -> Widget (Event TimelineMode)
renderGap zl (thisFocus, focused) duration' = container
  Box
  [classes ["gap", focusedClass focused], #orientation := OrientationHorizontal]
  [ boxChild
      False
      False
      0
      (widget
        Button
        [ on #clicked (CommandKeyMappedEvent (JumpFocus thisFocus))
        , #widthRequest := widthFromDuration zl duration'
        , #hasFocus := (focused == Focused)
        ]
      )
  ]

renderVideoPart
  :: ZoomLevel
  -> VideoPart (Focus SequenceFocusType, Focused)
  -> Widget (Event TimelineMode)
renderVideoPart zl = \case
  c@(VideoClip (thisFocus, focused) asset' _ _ _) ->
    renderClipAsset zl thisFocus focused asset' (durationOf AdjustedDuration c)
  VideoGap ann duration' -> renderGap zl ann duration'

renderAudioPart
  :: ZoomLevel
  -> AudioPart (Focus SequenceFocusType, Focused)
  -> Widget (Event TimelineMode)
renderAudioPart zl = \case
  AudioClip (thisFocus, focused) asset' ->
    renderClipAsset zl thisFocus focused asset' (durationOf AdjustedDuration asset')
  AudioGap ann duration' -> renderGap zl ann duration'

renderTimeline
  :: ZoomLevel
  -> Timeline (Focus SequenceFocusType, Focused)
  -> Widget (Event TimelineMode)
renderTimeline zl (Timeline sub) = container
  Box
  [classes ["composition", "timeline", emptyClass (null sub)]]
  (map (boxChild False False 0 . renderSequence zl) (toList sub))

renderSequence
  :: ZoomLevel
  -> Sequence (Focus SequenceFocusType, Focused)
  -> Widget (Event TimelineMode)
renderSequence zl (Sequence (_thisFocus, focused) sub) = container
  Box
  [ classes
      ["composition", "sequence", focusedClass focused, emptyClass (null sub)]
  ]
  (map (boxChild False False 0 . renderParallel zl) (toList sub))

renderParallel
  :: ZoomLevel
  -> Parallel (Focus SequenceFocusType, Focused)
  -> Widget (Event TimelineMode)
renderParallel zl (Parallel (_thisFocus, focused) vs as) = container
  Box
  [ #orientation := OrientationVertical
  , classes
    [ "composition"
    , "parallel"
    , focusedClass focused
    , emptyClass (null vs && null as)
    ]
  ]
  [ boxChild False False 0 $ container
    Box
    [classes ["video", focusedClass focused]]
    (map (boxChild False False 0 . renderVideoPart zl) vs)
  , boxChild False False 0 $ container
    Box
    [classes ["audio", focusedClass focused]]
    (map (boxChild False False 0 . renderAudioPart zl) as)
  ]

emptyClass :: Bool -> Text
emptyClass True  = "empty"
emptyClass False = "non-empty"

renderPreviewPane
  :: Maybe (FirstCompositionPart a) -> Widget (Event TimelineMode)
renderPreviewPane part = container
  Box
  [classes ["preview-pane"]]
  [ boxChild True True 0 $ case part of
      Just (FirstVideoPart (VideoClip _ _videoAsset _ _ thumbnail)) ->
        thumbnailPreview thumbnail
      Just (FirstAudioPart AudioClip{}) -> noPreviewAvailable
      Just (FirstVideoPart VideoGap{} ) -> widget Label [#label := "Video gap."]
      Just (FirstAudioPart AudioGap{} ) -> widget Label [#label := "Audio gap."]
      Nothing                           -> noPreviewAvailable
  ]
  where
    noPreviewAvailable = widget Label [#label := "No preview available."]

durationEntry :: Duration -> Widget Duration
durationEntry d = toDuration <$> numberInput NumberInputProperties
  { value              = durationToSeconds d
  , NumberInput.range              = (0, 1000000)
  , step               = 0.1
  , digits             = 2
  , numberInputClasses = []
  }
  where
    toDuration (NumberInputChanged n) = durationFromSeconds n

renderSidebar
  :: Maybe (SomeComposition a) -> Widget (Event TimelineMode)
renderSidebar (Just s) = case s of
  SomeSequence{}   -> widget Label [#label := "Sequence"]
  SomeParallel{}   -> widget Label [#label := "Parallel"]
  SomeVideoPart vp -> case vp of
    VideoClip _ _asset ts _speed _ ->
      container Box [#orientation := OrientationVertical]
      [ boxChild False False 5 $ widget Label [#label := "Start"]
      , boxChild False False 5 $ FocusedClipStartSet <$> durationEntry (spanStart ts)
      , boxChild False False 5 $ widget Label [#label := "End"]
      , boxChild False False 5 $ FocusedClipEndSet <$> durationEntry (spanEnd ts)
      ]
    VideoGap{}  -> widget Label [#label := "Video Gap"]
  SomeAudioPart ap' -> case ap' of
    AudioClip{} -> widget Label [#label := "Audio Clip"]
    AudioGap{}  -> widget Label [#label := "Audio Gap"]
renderSidebar Nothing                = widget Label [#label := "Nothing"]

renderSidebar
  :: Maybe (SomeComposition a) -> Widget (Event TimelineMode)
renderSidebar mcomp =
  container Box [ #orientation := OrientationVertical
                , #widthRequest := 40
                , classes ["sidebar"]]
            inner
  where
    inner = case mcomp of
      Just (SomeSequence s) -> do
        heading "Sequence"
        entry "Duration" (formatDuration (durationOf AdjustedDuration s))
      Just (SomeParallel p) -> do
        heading "Parallel"
        entry "Duration" (formatDuration (durationOf AdjustedDuration p))
      Just (SomeVideoPart (VideoClip _ asset ts speed _)) -> do
        heading "Video Clip"
        entry "Duration" (formatDuration (durationOf AdjustedDuration ts))
        entry "Speed" (formatSpeed speed)
        heading "Video Asset"
        entry "Original" (toS (asset ^. videoAssetMetadata . path . unOriginalPath))
        entry "Duration" (formatDuration (asset ^. videoAssetMetadata . duration))
      Just (SomeVideoPart (VideoGap _ d)) -> do
        heading "Video Gap"
        entry "Duration" (formatDuration d)
      Just (SomeAudioPart (AudioClip _ asset)) -> do
        heading "Audio Clip"
        entry "Duration" (formatDuration (asset ^. audioAssetMetadata . duration))
        heading "Audio Asset"
        entry "Original" (show (asset ^. audioAssetMetadata . path . unOriginalPath))
      Just (SomeAudioPart (AudioGap _ d)) -> do
        heading "Audio Gap"
        entry "Duration" (formatDuration d)
      Nothing ->
        boxChild False False 0 $
          widget Label [#label := "Nothing focused."]
    heading :: Text -> MarkupOf BoxChild (Event TimelineMode) ()
    heading t =
      boxChild False False 0 $
        widget Label [#label := t, classes ["sidebar-heading"]]
    entry :: Text -> Text -> MarkupOf BoxChild (Event TimelineMode) ()
    entry name value =
      boxChild False False 0 $
        container Box [#orientation := OrientationHorizontal, classes ["sidebar-entry"]] $ do
          boxChild True True 0 $
            widget Label [#label := name, #halign := AlignStart]
          boxChild False False 0 $
            widget Label [#label := value, #ellipsize := EllipsizeModeEnd]
    formatDuration :: Duration -> Text
    formatDuration = show . durationToSeconds

renderMainArea
  :: Focus SequenceFocusType -> Timeline () -> Widget (Event TimelineMode)
renderMainArea currentFocus' timeline' =
  container Box [#orientation := OrientationHorizontal] $ do
    boxChild True True 0 $
      renderPreviewPane (firstCompositionPart currentFocus' timeline')
    boxChild False False 0 $
      renderSidebar (atFocus currentFocus' timeline')

renderMenu :: Widget (Event TimelineMode)
renderMenu = container
  MenuBar
  []
  [ subMenu
    "Project"
    [ labelledItem SaveProject
    , labelledItem CloseProject
    , labelledItem Import
    , labelledItem Render
    , labelledItem Exit
    ]
  , subMenu
    "Timeline"
    [ labelledItem Copy
    , subMenu
      "Paste"
      [labelledItem (Paste PasteRightOf), labelledItem (Paste PasteLeftOf)]
    , insertSubMenu Video
    , insertSubMenu Audio
    , labelledItem Split
    , labelledItem Delete
    ]
  , subMenu "Help" [labelledItem Help]
  ]
  where
    labelledItem cmd =
      menuItem MenuItem [on #activate (CommandKeyMappedEvent cmd)]
        $ widget Label [#label := commandName cmd, #halign := AlignStart]
    insertSubMenu mediaType' = subMenu
      ("Insert " <> show mediaType')
      [ subMenu
        "Clip"
        (   enumFrom minBound
        <&> (labelledItem . InsertCommand (InsertClip (Just mediaType')))
        )
      , subMenu " Gap"
        (   enumFrom minBound
        <&> (labelledItem . InsertCommand (InsertGap (Just mediaType')))
        )
      ]

renderBottomBar :: TimelineModel -> Widget (Event TimelineMode)
renderBottomBar model = container
  Box
  [#orientation := OrientationHorizontal, classes ["bottom-bar"]]
  [ boxChild True True 0 $ widget
    Label
    [ classes ["status-message"]
    , #label := fromMaybe "" (model ^. statusMessage)
    , #ellipsize := EllipsizeModeEnd
    , #halign := AlignStart
    ]
  , boxChild False False 0 $ toZoomEvent <$> rangeSlider
    (RangeSliderProperties (1, 9) ["zoom-level"])
  ]
  where toZoomEvent (RangeSliderChanged d) = ZoomLevelChanged (ZoomLevel d)

timelineView :: TimelineModel -> Bin Window Widget (Event TimelineMode)
timelineView model =
  bin
      Window
      [ #title := (currentProject model ^. projectName)
      , on #deleteEvent (const (True, WindowClosed))
      ]
    $ container Box [#orientation := OrientationVertical]
    $ do
        boxChild False False 0 renderMenu
        boxChild True True 0 (renderMainArea (model ^. currentFocus) (currentProject model ^. timeline))
        boxChild False False 0 $ bin
          ScrolledWindow
          [ #hscrollbarPolicy := PolicyTypeAutomatic
          , #vscrollbarPolicy := PolicyTypeNever
          , classes ["timeline-container"]
          ]
          (renderTimeline (model ^. zoomLevel) focusedTimelineWithSetFoci)
        , boxChild False False 0 (renderBottomBar model)
        ]
  where
    focusedTimelineWithSetFoci :: Timeline (Focus SequenceFocusType, Focused)
    focusedTimelineWithSetFoci = withAllFoci (currentProject model ^. timeline)
      <&> \f -> (f, focusedState (model ^. currentFocus) f)
